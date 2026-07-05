"use server";

import crypto from "node:crypto";
import { revalidatePath } from "next/cache";
import bcrypt from "bcryptjs";
import { createClient } from "@/lib/supabase/server";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BCRYPT_ROUNDS = 10;

// Ambiguous-character-free alphabet so someone reading the URL out loud
// doesn't confuse 0/O or 1/l/i.
const SHARE_CODE_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";

function generateShareCode(): string {
  const bytes = crypto.randomBytes(10);
  let out = "";
  for (let i = 0; i < 10; i++) {
    out += SHARE_CODE_ALPHABET[bytes[i] % SHARE_CODE_ALPHABET.length];
  }
  return out;
}

function generateToken(): string {
  return crypto.randomBytes(24).toString("base64url");
}

type Result = { error: string | null };

async function loadOwnedEvent(eventId: string) {
  if (!UUID_RE.test(eventId)) return { error: "Invalid event id" as const };
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in" as const };
  const { data: event, error } = await supabase
    .from("events")
    .select("id, slug, share_code, share_password_hash, share_enabled")
    .eq("id", eventId)
    .maybeSingle();
  if (error) return { error: error.message };
  if (!event) return { error: "Event not found" as const };
  return { supabase, event };
}

export async function enableShare(
  _prev: Result,
  formData: FormData,
): Promise<Result> {
  const eventId = String(formData.get("event_id") ?? "");
  const password = String(formData.get("password") ?? "");
  if (!password || password.length < 4) {
    return { error: "Password must be at least 4 characters" };
  }

  const loaded = await loadOwnedEvent(eventId);
  if ("error" in loaded && !loaded.supabase) return { error: loaded.error };
  const { supabase, event } = loaded as NonNullable<{
    supabase: Awaited<ReturnType<typeof createClient>>;
    event: {
      id: string;
      slug: string;
      share_code: string | null;
      share_password_hash: string | null;
      share_enabled: boolean;
    };
  }>;

  const hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const shareCode = event.share_code ?? (await mintUniqueShareCode(supabase));

  const { error } = await supabase
    .from("events")
    .update({
      share_code: shareCode,
      share_password_hash: hash,
      share_enabled: true,
    })
    .eq("id", event.id);
  if (error) return { error: error.message };

  revalidatePath(`/events/${event.slug}`);
  return { error: null };
}

export async function disableShare(
  _prev: Result,
  formData: FormData,
): Promise<Result> {
  const eventId = String(formData.get("event_id") ?? "");
  const loaded = await loadOwnedEvent(eventId);
  if ("error" in loaded && !loaded.supabase) return { error: loaded.error };
  const { supabase, event } = loaded as NonNullable<{
    supabase: Awaited<ReturnType<typeof createClient>>;
    event: { id: string; slug: string };
  }>;

  const { error } = await supabase
    .from("events")
    .update({ share_enabled: false })
    .eq("id", event.id);
  if (error) return { error: error.message };

  revalidatePath(`/events/${event.slug}`);
  return { error: null };
}

export async function changeSharePassword(
  _prev: Result,
  formData: FormData,
): Promise<Result> {
  const eventId = String(formData.get("event_id") ?? "");
  const password = String(formData.get("password") ?? "");
  if (!password || password.length < 4) {
    return { error: "Password must be at least 4 characters" };
  }

  const loaded = await loadOwnedEvent(eventId);
  if ("error" in loaded && !loaded.supabase) return { error: loaded.error };
  const { supabase, event } = loaded as NonNullable<{
    supabase: Awaited<ReturnType<typeof createClient>>;
    event: { id: string; slug: string };
  }>;

  const hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const { error } = await supabase
    .from("events")
    .update({ share_password_hash: hash })
    .eq("id", event.id);
  if (error) return { error: error.message };

  revalidatePath(`/events/${event.slug}`);
  return { error: null };
}

export async function sendShareLink(
  _prev: Result,
  formData: FormData,
): Promise<Result> {
  const eventId = String(formData.get("event_id") ?? "");
  const channel = String(formData.get("channel") ?? "").trim();
  const recipient = String(formData.get("recipient") ?? "").trim();

  if (channel !== "sms" && channel !== "email") {
    return { error: "Pick SMS or email" };
  }
  if (!recipient) return { error: "Recipient required" };
  if (channel === "email" && !recipient.includes("@")) {
    return { error: "Enter a valid email" };
  }
  if (channel === "sms" && !/^\+?[0-9\s\-()]{7,}$/.test(recipient)) {
    return { error: "Enter a valid phone number" };
  }

  const loaded = await loadOwnedEvent(eventId);
  if ("error" in loaded && !loaded.supabase) return { error: loaded.error };
  const { supabase, event } = loaded as NonNullable<{
    supabase: Awaited<ReturnType<typeof createClient>>;
    event: {
      id: string;
      slug: string;
      share_enabled: boolean;
      share_code: string | null;
    };
  }>;

  if (!event.share_enabled || !event.share_code) {
    return { error: "Enable sharing before sending links" };
  }

  const { error } = await supabase.from("event_share_recipients").insert({
    event_id: event.id,
    channel,
    recipient,
    token: generateToken(),
  });
  if (error) return { error: error.message };

  revalidatePath(`/events/${event.slug}`);
  return { error: null };
}

export async function resendShareLink(
  _prev: Result,
  formData: FormData,
): Promise<Result> {
  const recipientId = String(formData.get("recipient_id") ?? "");
  const eventSlug = String(formData.get("event_slug") ?? "");
  if (!UUID_RE.test(recipientId)) return { error: "Invalid recipient id" };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in" };

  // RLS ensures we can only touch our own event's recipients.
  const { data: recipient, error: fetchErr } = await supabase
    .from("event_share_recipients")
    .select("id")
    .eq("id", recipientId)
    .maybeSingle();
  if (fetchErr) return { error: fetchErr.message };
  if (!recipient) return { error: "Recipient not found" };

  const { error: updateErr } = await supabase
    .from("event_share_recipients")
    .update({
      status: "pending",
      attempts: 0,
      last_attempt_at: null,
      sent_at: null,
      error: null,
    })
    .eq("id", recipientId);
  if (updateErr) return { error: updateErr.message };

  // The trigger only fires on INSERT — kick the Edge Function directly so
  // the resend goes out now instead of waiting for the retry cron.
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (supabaseUrl && serviceKey) {
    void fetch(`${supabaseUrl}/functions/v1/send-event-share`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ recipient_id: recipientId }),
    }).catch(() => {
      // fire-and-forget; retry cron will pick it up if this fails
    });
  }

  if (eventSlug) revalidatePath(`/events/${eventSlug}`);
  return { error: null };
}

async function mintUniqueShareCode(
  supabase: Awaited<ReturnType<typeof createClient>>,
): Promise<string> {
  for (let i = 0; i < 5; i++) {
    const candidate = generateShareCode();
    const { data } = await supabase
      .from("events")
      .select("id")
      .eq("share_code", candidate)
      .maybeSingle();
    if (!data) return candidate;
  }
  // 5 collisions on a 32^10 space is astronomically unlikely; if we hit it,
  // fall through and let the DB unique constraint surface a clean error.
  return generateShareCode();
}
