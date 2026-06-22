import Foundation
import Observation
import Supabase
import os

/// Source of autocomplete candidates for the DeliveryComposer's
/// email/phone inputs. Pulls from three places, all RLS-scoped to the
/// signed-in owner:
///
///   1. `contacts` rows for the current event (where invitee CSVs land)
///   2. past sms/email deliveries on this event
///   3. past sms/email deliveries on the owner's other events
///
/// Cached per event_id in memory. Designed so additional sources (a
/// dedicated invitee table, a server endpoint, etc.) can plug in by
/// extending `load(for:)` — DeliveryComposer never knows the difference.
@MainActor
@Observable
final class RecipientStore {
    static let shared = RecipientStore()
    private init() {}

    private let log = Logger(
        subsystem: "com.mazzillie.photoboot",
        category: "recipient-store"
    )

    private var byEvent: [UUID: [RecipientSuggestion]] = [:]
    private var loading: Set<UUID> = []

    /// Up to `limit` suggestions matching the requested channel and
    /// optional typed prefix. Empty prefix returns the top candidates so
    /// the field is useful before the user types anything.
    func suggestions(
        for eventId: UUID,
        channel: StripService.DeliveryChannel,
        prefix: String,
        limit: Int = 6
    ) -> [RecipientSuggestion] {
        let all = byEvent[eventId] ?? []
        let channelMatches = all.filter { matchesChannel($0, channel) }
        let normalizedPrefix = normalizePrefix(prefix, channel: channel)
        let pool: [RecipientSuggestion]
        if normalizedPrefix.isEmpty {
            pool = channelMatches
        } else {
            pool = channelMatches.filter {
                matchesPrefix($0, normalizedPrefix: normalizedPrefix, channel: channel)
            }
        }
        return Array(pool.prefix(limit))
    }

    /// Pulls all candidates for the event. Idempotent — coalesces
    /// concurrent calls, safe to re-run to refresh.
    func load(for event: Event) async {
        if loading.contains(event.id) { return }
        loading.insert(event.id)
        defer { loading.remove(event.id) }

        do {
            async let contactsResult = fetchContacts(eventId: event.id)
            async let deliveriesResult = fetchDeliveryRecipients()
            let merged = try await mergeSources(
                contacts: contactsResult,
                deliveries: deliveriesResult,
                currentEventId: event.id
            )
            byEvent[event.id] = merged
            log.info("loaded \(merged.count) suggestion(s) for event \(event.id.uuidString)")
        } catch {
            log.error("recipient load failed: \(error.localizedDescription)")
        }
    }

    /// After the user manually enters + sends to a recipient, persist
    /// them to the contacts table so future events (and a possible app
    /// restart) pick it up via the same `load(for:)` path.
    func recordManual(
        value: String,
        eventId: UUID,
        channel: StripService.DeliveryChannel
    ) async {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        struct UpsertContact: Encodable {
            let event_id: UUID
            let email: String?
            let phone: String?
            let source: String
        }

        let payload = UpsertContact(
            event_id: eventId,
            email: channel == .email ? trimmed.lowercased() : nil,
            phone: channel == .sms ? trimmed : nil,
            source: "manual"
        )

        do {
            try await SupabaseService.shared.client
                .from("contacts")
                .insert(payload)
                .execute()
        } catch {
            // Best-effort — don't block the user's send on a save failure.
            log.error("recordManual failed: \(error.localizedDescription)")
        }

        let suggestion = RecipientSuggestion(
            value: trimmed,
            origin: .eventContact
        )
        var current = byEvent[eventId] ?? []
        if !current.contains(where: { $0.matches(value: trimmed, channel: channel) }) {
            current.insert(suggestion, at: 0)
            byEvent[eventId] = current
        }
    }

    // MARK: - Sources

    private struct ContactRow: Decodable {
        let email: String?
        let phone: String?
    }

    private func fetchContacts(eventId: UUID) async throws -> [ContactRow] {
        try await SupabaseService.shared.client
            .from("contacts")
            .select("email, phone")
            .eq("event_id", value: eventId)
            .execute()
            .value
    }

    private struct DeliveryRecipientRow: Decodable {
        let channel: String
        let recipient: String?
        let strips: StripRef

        struct StripRef: Decodable {
            let event_id: UUID
        }
    }

    private func fetchDeliveryRecipients() async throws -> [DeliveryRecipientRow] {
        // RLS scopes to the user's events; the inner join + channel filter
        // strip out the print/airdrop rows (which have null recipients).
        try await SupabaseService.shared.client
            .from("deliveries")
            .select("channel, recipient, strips!inner(event_id)")
            .in("channel", values: ["sms", "email"])
            .execute()
            .value
    }

    // MARK: - Merge

    private func mergeSources(
        contacts: [ContactRow],
        deliveries: [DeliveryRecipientRow],
        currentEventId: UUID
    ) -> [RecipientSuggestion] {
        var byKey: [String: RecipientSuggestion] = [:]

        // Contacts get highest priority — they're the cleanest source.
        for c in contacts {
            if let email = c.email, !email.isEmpty {
                byKey["email:\(email.lowercased())"] = RecipientSuggestion(
                    value: email,
                    origin: .eventContact
                )
            }
            if let phone = c.phone, !phone.isEmpty {
                byKey["sms:\(phone.filter(\.isNumber))"] = RecipientSuggestion(
                    value: phone,
                    origin: .eventContact
                )
            }
        }

        // Deliveries fill in only entries not already covered by contacts.
        // Distinguish this-event history from cross-event so the UI can
        // surface "from past event" candidates with a label.
        for d in deliveries {
            guard let recipient = d.recipient, !recipient.isEmpty else { continue }
            let key: String
            switch d.channel {
            case "email": key = "email:\(recipient.lowercased())"
            case "sms": key = "sms:\(recipient.filter(\.isNumber))"
            default: continue
            }
            if byKey[key] != nil { continue }
            let origin: RecipientSuggestion.Origin =
                d.strips.event_id == currentEventId ? .eventHistory : .crossEvent
            byKey[key] = RecipientSuggestion(value: recipient, origin: origin)
        }

        return byKey.values.sorted { lhs, rhs in
            if lhs.origin != rhs.origin {
                return originPriority(lhs.origin) < originPriority(rhs.origin)
            }
            return lhs.value.lowercased() < rhs.value.lowercased()
        }
    }

    // MARK: - Matching helpers

    private func matchesChannel(
        _ s: RecipientSuggestion,
        _ channel: StripService.DeliveryChannel
    ) -> Bool {
        switch channel {
        case .email: s.value.contains("@")
        case .sms: !s.value.contains("@")
        }
    }

    private func normalizePrefix(
        _ s: String,
        channel: StripService.DeliveryChannel
    ) -> String {
        switch channel {
        case .email: s.trimmingCharacters(in: .whitespaces).lowercased()
        case .sms: s.filter(\.isNumber)
        }
    }

    private func matchesPrefix(
        _ s: RecipientSuggestion,
        normalizedPrefix p: String,
        channel: StripService.DeliveryChannel
    ) -> Bool {
        switch channel {
        case .email:
            return s.value.lowercased().contains(p)
        case .sms:
            return s.value.filter(\.isNumber).contains(p)
        }
    }

    private func originPriority(_ o: RecipientSuggestion.Origin) -> Int {
        switch o {
        case .eventContact: 0
        case .eventHistory: 1
        case .crossEvent: 2
        }
    }
}

struct RecipientSuggestion: Identifiable, Hashable {
    let value: String
    let origin: Origin

    var id: String { "\(origin.rawValue)|\(value)" }

    enum Origin: String, Hashable {
        case eventContact
        case eventHistory
        case crossEvent

        var label: String {
            switch self {
            case .eventContact: "Contact"
            case .eventHistory: "Recent"
            case .crossEvent: "Past event"
            }
        }
    }

    func matches(value other: String, channel: StripService.DeliveryChannel) -> Bool {
        switch channel {
        case .email: return value.lowercased() == other.lowercased()
        case .sms: return value.filter(\.isNumber) == other.filter(\.isNumber)
        }
    }
}
