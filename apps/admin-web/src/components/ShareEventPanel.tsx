"use client";

import { useActionState, useState } from "react";
import {
  changeSharePassword,
  disableShare,
  enableShare,
  resendShareLink,
  sendShareLink,
} from "@/app/events/[slug]/share-actions";

type Result = { error: string | null };
const initial: Result = { error: null };

export interface ShareRecipient {
  id: string;
  channel: "sms" | "email";
  recipient: string;
  status: "pending" | "sent" | "failed";
  sent_at: string | null;
  error: string | null;
  created_at: string;
}

interface Props {
  eventId: string;
  eventSlug: string;
  shareCode: string | null;
  shareEnabled: boolean;
  hasPassword: boolean;
  publicOrigin: string;
  recipients: ShareRecipient[];
}

export function ShareEventPanel({
  eventId,
  eventSlug,
  shareCode,
  shareEnabled,
  hasPassword,
  publicOrigin,
  recipients,
}: Props) {
  return (
    <section className="mt-10">
      <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-500">
        Share
      </h2>
      <div className="mt-3 space-y-4 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-zinc-200">
        {!shareEnabled ? (
          <EnableForm eventId={eventId} hasExistingPassword={hasPassword} />
        ) : (
          <>
            {shareCode ? (
              <SharedLinkRow url={`${publicOrigin}/e/${shareCode}`} />
            ) : null}

            <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
              <ChangePasswordForm eventId={eventId} />
              <DisableForm eventId={eventId} />
            </div>

            <hr className="border-zinc-200" />

            <SendForm eventId={eventId} />

            {recipients.length > 0 ? (
              <RecipientList recipients={recipients} eventSlug={eventSlug} />
            ) : null}
          </>
        )}
      </div>
    </section>
  );
}

function SharedLinkRow({ url }: { url: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // clipboard blocked; user can still select the text
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <code className="min-w-0 flex-1 truncate rounded-md bg-zinc-50 px-2.5 py-1.5 text-sm text-zinc-700 ring-1 ring-zinc-200">
        {url}
      </code>
      <button
        type="button"
        onClick={copy}
        className="rounded-full bg-white px-3 py-1.5 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-200 transition hover:bg-zinc-50"
      >
        {copied ? "Copied ✓" : "Copy link"}
      </button>
    </div>
  );
}

function EnableForm({
  eventId,
  hasExistingPassword,
}: {
  eventId: string;
  hasExistingPassword: boolean;
}) {
  const [state, formAction, pending] = useActionState<Result, FormData>(
    enableShare,
    initial,
  );
  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="event_id" value={eventId} />
      <p className="text-sm text-zinc-600">
        Turn on a public gallery URL for this event. Recipients need the
        password, or the magic link you send them by email/SMS.
      </p>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <label className="flex-1">
          <span className="block text-sm font-medium text-zinc-700">
            Password
          </span>
          <input
            name="password"
            type="text"
            required
            minLength={4}
            placeholder={
              hasExistingPassword ? "Set a new password" : "Choose a password"
            }
            className="mt-1 w-full rounded-lg border-0 bg-white px-3 py-2 ring-1 ring-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-600"
          />
        </label>
        <button
          type="submit"
          disabled={pending}
          className="ig-gradient rounded-md px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:opacity-90 disabled:opacity-60"
        >
          {pending ? "Enabling…" : "Enable sharing"}
        </button>
      </div>
      {state.error ? (
        <p className="text-xs text-rose-600">{state.error}</p>
      ) : null}
    </form>
  );
}

function DisableForm({ eventId }: { eventId: string }) {
  const [state, formAction, pending] = useActionState<Result, FormData>(
    disableShare,
    initial,
  );
  return (
    <form action={formAction}>
      <input type="hidden" name="event_id" value={eventId} />
      <button
        type="submit"
        disabled={pending}
        className="text-xs font-semibold text-rose-600 hover:text-rose-700 disabled:opacity-60"
      >
        {pending ? "Disabling…" : "Disable sharing"}
      </button>
      {state.error ? (
        <span className="ml-2 text-xs text-rose-600">{state.error}</span>
      ) : null}
    </form>
  );
}

function ChangePasswordForm({ eventId }: { eventId: string }) {
  const [open, setOpen] = useState(false);
  const [state, formAction, pending] = useActionState<Result, FormData>(
    changeSharePassword,
    initial,
  );
  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="text-xs font-semibold text-zinc-600 hover:text-zinc-900"
      >
        Change password
      </button>
    );
  }
  return (
    <form action={formAction} className="flex items-center gap-2">
      <input type="hidden" name="event_id" value={eventId} />
      <input
        name="password"
        type="text"
        required
        minLength={4}
        autoFocus
        placeholder="New password"
        className="rounded-md border-0 bg-white px-2 py-1 text-xs ring-1 ring-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-600"
      />
      <button
        type="submit"
        disabled={pending}
        className="rounded-full bg-zinc-900 px-2.5 py-1 text-xs font-semibold text-white disabled:opacity-60"
      >
        {pending ? "…" : "Save"}
      </button>
      <button
        type="button"
        onClick={() => setOpen(false)}
        className="text-xs text-zinc-500 hover:text-zinc-900"
      >
        Cancel
      </button>
      {state.error ? (
        <span className="text-xs text-rose-600">{state.error}</span>
      ) : null}
    </form>
  );
}

function SendForm({ eventId }: { eventId: string }) {
  const [state, formAction, pending] = useActionState<Result, FormData>(
    sendShareLink,
    initial,
  );
  const [channel, setChannel] = useState<"email" | "sms">("email");
  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="event_id" value={eventId} />
      <p className="text-sm font-medium text-zinc-700">Send a magic link</p>
      <div className="flex items-center gap-4 text-sm text-zinc-600">
        <label className="flex items-center gap-1.5">
          <input
            type="radio"
            name="channel"
            value="email"
            checked={channel === "email"}
            onChange={() => setChannel("email")}
          />
          <span>Email</span>
        </label>
        <label className="flex items-center gap-1.5">
          <input
            type="radio"
            name="channel"
            value="sms"
            checked={channel === "sms"}
            onChange={() => setChannel("sms")}
          />
          <span>SMS</span>
        </label>
      </div>
      <div className="flex flex-col gap-2 sm:flex-row">
        <input
          key={channel}
          name="recipient"
          type={channel === "email" ? "email" : "tel"}
          required
          placeholder={
            channel === "email" ? "friend@example.com" : "+15551234567"
          }
          className="flex-1 rounded-lg border-0 bg-white px-3 py-2 text-sm ring-1 ring-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-600"
        />
        <button
          type="submit"
          disabled={pending}
          className="ig-gradient rounded-md px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:opacity-90 disabled:opacity-60"
        >
          {pending ? "Sending…" : "Send link"}
        </button>
      </div>
      {state.error ? (
        <p className="text-xs text-rose-600">{state.error}</p>
      ) : null}
    </form>
  );
}

function RecipientList({
  recipients,
  eventSlug,
}: {
  recipients: ShareRecipient[];
  eventSlug: string;
}) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
        Recipients ({recipients.length})
      </p>
      <ul className="divide-y divide-zinc-100">
        {recipients.map((r) => (
          <RecipientRow key={r.id} r={r} eventSlug={eventSlug} />
        ))}
      </ul>
    </div>
  );
}

function RecipientRow({
  r,
  eventSlug,
}: {
  r: ShareRecipient;
  eventSlug: string;
}) {
  const [state, formAction, pending] = useActionState<Result, FormData>(
    resendShareLink,
    initial,
  );
  const statusColor =
    r.status === "sent"
      ? "text-emerald-600"
      : r.status === "failed"
        ? "text-rose-600"
        : "text-amber-600";
  const sentAt = r.sent_at
    ? new Date(r.sent_at).toLocaleString(undefined, {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      })
    : null;
  const errorText = state.error ?? r.error;
  return (
    <li className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
      <div className="flex min-w-0 items-center gap-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
          {r.channel}
        </span>
        <span className="min-w-0 truncate text-zinc-800">{r.recipient}</span>
      </div>
      <div className="flex items-center gap-3">
        <span className={`text-xs font-medium ${statusColor}`}>{r.status}</span>
        {sentAt ? (
          <span className="text-xs text-zinc-400">{sentAt}</span>
        ) : null}
        <form action={formAction}>
          <input type="hidden" name="recipient_id" value={r.id} />
          <input type="hidden" name="event_slug" value={eventSlug} />
          <button
            type="submit"
            disabled={pending}
            className="rounded-full bg-white px-2.5 py-1 text-xs font-semibold text-zinc-900 shadow-sm ring-1 ring-zinc-200 transition hover:bg-zinc-50 disabled:opacity-60"
          >
            {pending ? "…" : "Resend"}
          </button>
        </form>
      </div>
      {errorText ? (
        <p className="w-full truncate text-xs text-rose-600">{errorText}</p>
      ) : null}
    </li>
  );
}
