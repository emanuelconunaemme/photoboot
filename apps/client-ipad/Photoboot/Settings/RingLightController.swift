import CoreBluetooth
import Foundation
import Observation
import UIKit
import os

/// BLE driver for the photo booth stand's 22" ring light (ELK-BLEDOM
/// chipset, advertised as `MELK-*`). Singleton; lives for the life of
/// the app and is driven from the Settings sheet.
///
/// Pairing flow: user taps Scan, we either reconnect to a previously
/// saved peripheral by identifier or scan for one advertising the
/// `MELK-` name prefix. Once connected, color / brightness / on-off
/// frames are written without response on characteristic FFF3.
@MainActor
@Observable
final class RingLightController: NSObject {
    static let shared = RingLightController()

    enum State: Equatable {
        case idle
        case unauthorized
        case poweredOff
        case scanning
        case connecting(name: String)
        case connected(name: String)
        case disconnected
        case noneFound
        case failed(reason: String)

        var summary: String {
            switch self {
            case .idle:              return "Not connected"
            case .unauthorized:      return "Bluetooth access denied"
            case .poweredOff:        return "Bluetooth is off"
            case .scanning:          return "Scanning…"
            case .connecting(let n): return "Connecting to \(n)…"
            case .connected(let n):  return "Connected to \(n)"
            case .disconnected:      return "Disconnected"
            case .noneFound:         return "No ring light found"
            case .failed(let r):     return r
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var isBusy: Bool {
            switch self {
            case .scanning, .connecting: return true
            default: return false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var isOn: Bool = true
    private(set) var brightness: Int = 100
    private(set) var colorHex: String = "#FFFFFF"

    /// Whether a previously-paired peripheral identifier is on file. The
    /// Settings sheet uses this to silently reconnect on appear instead
    /// of waiting for the user to tap Scan again.
    var hasSavedPeripheral: Bool { savedPeripheralID != nil }

    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "ring-light")
    private let defaults = UserDefaults.standard
    private enum Key {
        static let peripheralUUID = "photoboot.ringLight.peripheralUUID"
        static let colorHex = "photoboot.ringLight.colorHex"
        static let brightness = "photoboot.ringLight.brightness"
        static let isOn = "photoboot.ringLight.isOn"
    }

    private static let serviceUUID = CBUUID(string: "FFF0")
    private static let writeUUID = CBUUID(string: "FFF3")
    private static let scanTimeout: Duration = .seconds(8)

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var scanTimeoutTask: Task<Void, Never>?
    private var savedPeripheralID: UUID?

    private override init() {
        super.init()
        if let hex = defaults.string(forKey: Key.colorHex) {
            colorHex = hex
        }
        let storedBright = defaults.integer(forKey: Key.brightness)
        if storedBright > 0 { brightness = storedBright }
        if defaults.object(forKey: Key.isOn) != nil {
            isOn = defaults.bool(forKey: Key.isOn)
        }
        if let s = defaults.string(forKey: Key.peripheralUUID), let id = UUID(uuidString: s) {
            savedPeripheralID = id
        }
    }

    // MARK: - Lifecycle

    /// Spin up the central manager. First call triggers the system BLE
    /// permission prompt; no scan happens until `scan()`.
    func start() {
        if central != nil { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Reconnect to the saved peripheral if we have one, otherwise scan
    /// the air for a `MELK-` advertiser. Safe to call repeatedly.
    func scan() {
        start()
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            beginScanOrRetrieve()
        case .poweredOff:
            state = .poweredOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .failed(reason: "Bluetooth not supported on this device")
        case .resetting, .unknown:
            // Pending — centralManagerDidUpdateState will retry once
            // CoreBluetooth settles.
            state = .scanning
        @unknown default:
            break
        }
    }

    func disconnect() {
        scanTimeoutTask?.cancel()
        if let central, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            state = .disconnected
        }
    }

    private func beginScanOrRetrieve() {
        guard let central else { return }
        if let id = savedPeripheralID,
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            log.info("retrieved known peripheral \(known.identifier.uuidString, privacy: .public)")
            connect(known)
            return
        }
        startActualScan()
    }

    private func startActualScan() {
        guard let central else { return }
        state = .scanning
        log.info("scanning for ring light")
        // ELK-BLEDOM devices don't advertise their service UUID, so we
        // can't filter by service — pass nil and match by name prefix
        // inside didDiscover.
        central.scanForPeripherals(withServices: nil, options: nil)
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.scanTimeout)
            guard let self, !Task.isCancelled else { return }
            self.central?.stopScan()
            if case .scanning = self.state {
                self.state = .noneFound
            }
        }
    }

    private func connect(_ p: CBPeripheral) {
        guard let central else { return }
        peripheral = p
        p.delegate = self
        let label = p.name ?? "Ring light"
        state = .connecting(name: label)
        central.stopScan()
        scanTimeoutTask?.cancel()
        log.info("connecting to \(label, privacy: .public)")
        central.connect(p, options: nil)
    }

    // MARK: - Commands

    func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: Key.isOn)
        write(frame: on ? .on : .off)
    }

    func setBrightness(_ value: Int) {
        let clamped = max(0, min(100, value))
        brightness = clamped
        defaults.set(clamped, forKey: Key.brightness)
        write(frame: .brightness(clamped))
    }

    func setColor(hex: String) {
        colorHex = hex
        defaults.set(hex, forKey: Key.colorHex)
        let (r, g, b) = Self.rgb(fromHex: hex)
        // Picking a color implies "make the light show this color" — if
        // it was off, turn it on first so the user sees the result.
        if !isOn { setOn(true) }
        write(frame: .color(r: r, g: g, b: b))
    }

    private func write(frame: Frame) {
        guard let peripheral, let writeChar else { return }
        peripheral.writeValue(frame.bytes, for: writeChar, type: .withoutResponse)
    }

    // MARK: - Wire protocol
    // 9-byte frames documented in the controller's stock app. All
    // writes are without-response on characteristic FFF3.

    private enum Frame {
        case on
        case off
        case color(r: UInt8, g: UInt8, b: UInt8)
        case brightness(Int)

        var bytes: Data {
            switch self {
            case .on:
                return Data([0x7E, 0x00, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF])
            case .off:
                return Data([0x7E, 0x00, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF])
            case .color(let r, let g, let b):
                return Data([0x7E, 0x00, 0x05, 0x03, r, g, b, 0x00, 0xEF])
            case .brightness(let n):
                return Data([0x7E, 0x00, 0x01, UInt8(clamping: n), 0x00, 0x00, 0x00, 0x00, 0xEF])
            }
        }
    }

    private static func rgb(fromHex hex: String) -> (UInt8, UInt8, UInt8) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return (255, 255, 255)
        }
        return (
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        )
    }
}

extension RingLightController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = central.state
        Task { @MainActor in
            switch s {
            case .poweredOn:
                self.beginScanOrRetrieve()
            case .poweredOff:
                self.state = .poweredOff
                self.writeChar = nil
            case .unauthorized:
                self.state = .unauthorized
            case .unsupported:
                self.state = .failed(reason: "Bluetooth not supported on this device")
            case .resetting, .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let advertised = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let name = (peripheral.name ?? advertised).uppercased()
        guard name.hasPrefix("MELK-") || name.hasPrefix("ELK-BLEDOM") else { return }
        Task { @MainActor in
            // Only connect to the first match — multiple identical lights
            // in earshot is not a real scenario for this stand.
            guard !self.state.isConnected, case .scanning = self.state else { return }
            self.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.log.info("connected, discovering services")
            peripheral.delegate = self
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        let msg = error?.localizedDescription
        Task { @MainActor in
            self.writeChar = nil
            self.state = .failed(reason: msg ?? "Couldn't connect to ring light")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.writeChar = nil
            self.state = .disconnected
        }
    }
}

extension RingLightController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }
            for svc in services where svc.uuid == Self.serviceUUID {
                peripheral.discoverCharacteristics([Self.writeUUID], for: svc)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        let id = peripheral.identifier
        let name = peripheral.name ?? "Ring light"
        let found = service.characteristics?.first(where: { $0.uuid == Self.writeUUID })
        Task { @MainActor in
            guard let found else {
                self.state = .failed(reason: "Ring light is missing the expected control characteristic")
                return
            }
            self.writeChar = found
            self.state = .connected(name: name)
            self.defaults.set(id.uuidString, forKey: Key.peripheralUUID)
            self.savedPeripheralID = id
            // Replay the last-known on/color/brightness so the light
            // visually matches the iPad's stored state immediately.
            self.write(frame: self.isOn ? .on : .off)
            if self.isOn {
                let (r, g, b) = Self.rgb(fromHex: self.colorHex)
                self.write(frame: .color(r: r, g: g, b: b))
                self.write(frame: .brightness(self.brightness))
            }
        }
    }
}
