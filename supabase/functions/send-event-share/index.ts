// Dispatches a single pending event_share_recipient (SMS via Twilio, email
// via Resend). Invoked by the on_event_share_recipient_insert trigger, and
// by retry_pending_event_shares via pg_cron. Also callable directly with
// { recipient_id: uuid } in the body.
//
// The URL embedded in the message is /e/{share_code}/t/{token}, which is a
// Route Handler that verifies the token, sets an auth cookie, and redirects
// to the gallery — bypassing the password prompt.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

class DeliveryError extends Error {
  retryable: boolean;
  constructor(message: string, retryable: boolean) {
    super(message);
    this.retryable = retryable;
  }
}

function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}

interface RecipientRow {
  id: string;
  event_id: string;
  channel: "sms" | "email";
  recipient: string;
  token: string;
  status: "pending" | "sent" | "failed";
  attempts: number;
}

interface EventRow {
  name: string;
  event_date: string | null;
  share_code: string | null;
  share_enabled: boolean;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLIC_URL = Deno.env.get("PUBLIC_URL") ?? "";

const TWILIO_SID = Deno.env.get("TWILIO_ACCOUNT_SID");
const TWILIO_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN");
const TWILIO_FROM = Deno.env.get("TWILIO_FROM_NUMBER");

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const RESEND_FROM = Deno.env.get("RESEND_FROM_ADDRESS");

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req) => {
  try {
    const { recipient_id } = (await req.json().catch(() => ({}))) as {
      recipient_id?: string;
    };
    if (!recipient_id) return json({ error: "Missing recipient_id" }, 400);

    const { data: recipient, error: rErr } = await supabase
      .from("event_share_recipients")
      .select("id, event_id, channel, recipient, token, status, attempts")
      .eq("id", recipient_id)
      .maybeSingle();
    if (rErr) return json({ error: rErr.message }, 500);
    if (!recipient) return json({ error: "Recipient not found" }, 404);
    if (recipient.status === "sent") return json({ ok: true, already: true });
    const r = recipient as RecipientRow;

    const { data: event, error: eErr } = await supabase
      .from("events")
      .select("name, event_date, share_code, share_enabled")
      .eq("id", r.event_id)
      .maybeSingle();
    if (eErr) return json({ error: eErr.message }, 500);
    if (!event) return json({ error: "Event not found" }, 404);
    const e = event as EventRow;

    if (!e.share_enabled || !e.share_code) {
      // Share got toggled off between insert and dispatch — mark failed so
      // the retry cron doesn't keep firing.
      await supabase
        .from("event_share_recipients")
        .update({
          status: "failed",
          attempts: r.attempts + 1,
          last_attempt_at: new Date().toISOString(),
          error: "Share disabled",
        })
        .eq("id", r.id);
      return json({ error: "Share disabled" }, 400);
    }

    const url = `${PUBLIC_URL.replace(/\/$/, "")}/e/${e.share_code}/t/${r.token}`;

    try {
      if (r.channel === "sms") {
        await sendSms(r.recipient, e.name, url);
      } else if (r.channel === "email") {
        await sendEmail(r.recipient, e.name, e.event_date, url);
      } else {
        throw new Error(`Unknown channel: ${r.channel}`);
      }

      await supabase
        .from("event_share_recipients")
        .update({
          status: "sent",
          sent_at: new Date().toISOString(),
          attempts: r.attempts + 1,
          last_attempt_at: new Date().toISOString(),
          error: null,
        })
        .eq("id", r.id);

      return json({ ok: true });
    } catch (sendErr) {
      const message = sendErr instanceof Error ? sendErr.message : String(sendErr);
      const retryable =
        sendErr instanceof DeliveryError ? sendErr.retryable : true;
      await supabase
        .from("event_share_recipients")
        .update({
          status: retryable ? "pending" : "failed",
          attempts: r.attempts + 1,
          last_attempt_at: new Date().toISOString(),
          error: message,
        })
        .eq("id", r.id);
      return json({ error: message, retryable }, retryable ? 503 : 502);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return json({ error: message }, 500);
  }
});

async function sendSms(to: string, eventName: string, url: string) {
  if (!TWILIO_SID || !TWILIO_TOKEN || !TWILIO_FROM) {
    throw new DeliveryError(
      "Twilio not configured (TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN/TWILIO_FROM_NUMBER)",
      false,
    );
  }
  const body = `Photos from ${eventName} are ready! View the gallery: ${url} Reply STOP to unsubscribe.`;
  const res = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_SID}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: "Basic " + btoa(`${TWILIO_SID}:${TWILIO_TOKEN}`),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ To: to, From: TWILIO_FROM, Body: body }).toString(),
    },
  );
  if (!res.ok) {
    const text = await res.text();
    throw new DeliveryError(
      `Twilio ${res.status}: ${text}`,
      isRetryableStatus(res.status),
    );
  }
}

async function sendEmail(
  to: string,
  eventName: string,
  eventDate: string | null,
  url: string,
) {
  if (!RESEND_API_KEY || !RESEND_FROM) {
    throw new DeliveryError(
      "Resend not configured (RESEND_API_KEY/RESEND_FROM_ADDRESS)",
      false,
    );
  }
  const safeName = escapeHtml(eventName);
  const dateLine = eventDate
    ? `<p style="color:#888;font-size:14px;margin:0 0 16px 0;">${escapeHtml(eventDate)}</p>`
    : "";
  const html = `
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;">
      <h1 style="margin:0 0 8px 0;font-size:28px;">Photos from ${safeName}</h1>
      <p style="margin:0 0 4px 0;color:#444;">The whole gallery is ready to browse.</p>
      ${dateLine}
      <p style="margin:24px 0;">
        <a href="${url}" style="display:inline-block;padding:14px 28px;background:linear-gradient(135deg,#833AB4 0%,#E1306C 50%,#FCB045 100%);color:white;text-decoration:none;border-radius:10px;font-weight:600;">View gallery</a>
      </p>
      <p style="color:#888;font-size:12px;margin-top:32px;">Or copy this link:<br><a href="${url}" style="color:#888;">${url}</a></p>
    </div>
  `;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: RESEND_FROM,
      to,
      subject: `Photos from ${eventName}`,
      html,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new DeliveryError(
      `Resend ${res.status}: ${text}`,
      isRetryableStatus(res.status),
    );
  }
}

function escapeHtml(s: string): string {
  return s.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!,
  );
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
