// Dispatches a single pending delivery (SMS via Twilio, email via Resend).
// Invoked by Postgres triggers on:
//   - deliveries INSERT, if the strip already has a composite_path
//   - strips UPDATE, when composite_path transitions from NULL → non-null
//     (fans out any pending deliveries for that strip)
//
// Also callable directly with { delivery_id: uuid } in the body.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface DeliveryRow {
  id: string;
  strip_id: string;
  channel: "sms" | "email";
  recipient: string;
  status: "pending" | "sent" | "failed";
  attempts: number;
}

interface StripRow {
  id: string;
  composite_path: string | null;
  event_id: string;
}

interface EventRow {
  name: string;
  event_date: string | null;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLIC_URL = Deno.env.get("PUBLIC_URL") ?? ""; // e.g. https://photoboot-xxx.vercel.app

const TWILIO_SID = Deno.env.get("TWILIO_ACCOUNT_SID");
const TWILIO_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN");
const TWILIO_FROM = Deno.env.get("TWILIO_FROM_NUMBER");

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const RESEND_FROM = Deno.env.get("RESEND_FROM_ADDRESS"); // e.g. "Photoboot <photos@yourdomain.com>"

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req) => {
  try {
    const { delivery_id } = (await req.json().catch(() => ({}))) as {
      delivery_id?: string;
    };
    if (!delivery_id) {
      return json({ error: "Missing delivery_id" }, 400);
    }

    const { data: delivery, error: deliveryErr } = await supabase
      .from("deliveries")
      .select("id, strip_id, channel, recipient, status, attempts")
      .eq("id", delivery_id)
      .maybeSingle();
    if (deliveryErr) return json({ error: deliveryErr.message }, 500);
    if (!delivery) return json({ error: "Delivery not found" }, 404);
    if (delivery.status === "sent") return json({ ok: true, already: true });

    const { data: strip, error: stripErr } = await supabase
      .from("strips")
      .select("id, composite_path, event_id")
      .eq("id", (delivery as DeliveryRow).strip_id)
      .maybeSingle();
    if (stripErr) return json({ error: stripErr.message }, 500);
    if (!strip) return json({ error: "Strip not found" }, 404);
    if (!(strip as StripRow).composite_path) {
      return json({ ok: false, reason: "strip not ready" }, 202);
    }

    const { data: event, error: eventErr } = await supabase
      .from("events")
      .select("name, event_date")
      .eq("id", (strip as StripRow).event_id)
      .maybeSingle();
    if (eventErr) return json({ error: eventErr.message }, 500);
    if (!event) return json({ error: "Event not found" }, 404);

    const stripUrl = `${PUBLIC_URL.replace(/\/$/, "")}/p/${(strip as StripRow).id}`;
    const d = delivery as DeliveryRow;
    const e = event as EventRow;

    try {
      if (d.channel === "sms") {
        await sendSms(d.recipient, e.name, stripUrl);
      } else if (d.channel === "email") {
        await sendEmail(d.recipient, e.name, e.event_date, stripUrl);
      } else {
        throw new Error(`Unknown channel: ${d.channel}`);
      }

      await supabase
        .from("deliveries")
        .update({
          status: "sent",
          sent_at: new Date().toISOString(),
          attempts: d.attempts + 1,
          error: null,
        })
        .eq("id", d.id);

      return json({ ok: true });
    } catch (sendErr) {
      const message = sendErr instanceof Error ? sendErr.message : String(sendErr);
      await supabase
        .from("deliveries")
        .update({
          status: "failed",
          attempts: d.attempts + 1,
          error: message,
        })
        .eq("id", d.id);
      return json({ error: message }, 502);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return json({ error: message }, 500);
  }
});

async function sendSms(to: string, eventName: string, url: string) {
  if (!TWILIO_SID || !TWILIO_TOKEN || !TWILIO_FROM) {
    throw new Error("Twilio not configured (TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN/TWILIO_FROM_NUMBER)");
  }
  const body = `Your photo from ${eventName}: ${url}`;
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
    throw new Error(`Twilio ${res.status}: ${text}`);
  }
}

async function sendEmail(
  to: string,
  eventName: string,
  eventDate: string | null,
  url: string,
) {
  if (!RESEND_API_KEY || !RESEND_FROM) {
    throw new Error("Resend not configured (RESEND_API_KEY/RESEND_FROM_ADDRESS)");
  }
  const safeName = escapeHtml(eventName);
  const dateLine = eventDate ? `<p style="color:#888;font-size:14px;margin:0 0 16px 0;">${escapeHtml(eventDate)}</p>` : "";
  const html = `
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;">
      <h1 style="margin:0 0 8px 0;font-size:28px;">Here's your photo strip!</h1>
      <p style="margin:0 0 4px 0;color:#444;">From <strong>${safeName}</strong></p>
      ${dateLine}
      <p style="margin:24px 0;">
        <a href="${url}" style="display:inline-block;padding:14px 28px;background:linear-gradient(135deg,#833AB4 0%,#E1306C 50%,#FCB045 100%);color:white;text-decoration:none;border-radius:10px;font-weight:600;">View your strip</a>
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
      subject: `Your photo from ${eventName}`,
      html,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Resend ${res.status}: ${text}`);
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
