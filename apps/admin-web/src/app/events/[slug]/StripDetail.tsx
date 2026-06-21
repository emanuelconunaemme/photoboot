"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { StripFormat } from "@/lib/database";

interface Props {
  open: boolean;
  onClose: () => void;
  onDeleted: (stripId: string) => void;
  stripId: string;
  composite2x6Path: string | null;
  composite4x6Path: string | null;
  imageUrl: string | null;
  format: StripFormat;
  eventName: string;
  createdAt: string;
}

type View = "actions" | "email" | "sms" | "confirm-delete";

export function StripDetail({
  open,
  onClose,
  onDeleted,
  stripId,
  composite2x6Path,
  composite4x6Path,
  imageUrl,
  format,
  eventName,
  createdAt,
}: Props) {
  const [view, setView] = useState<View>("actions");
  const [recipient, setRecipient] = useState("");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !busy) onClose();
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [open, busy, onClose]);

  if (!open) return null;

  function flashStatus(message: string) {
    setStatus(message);
    setTimeout(() => setStatus(null), 2500);
  }

  async function handleDownload() {
    if (!imageUrl) return;
    setBusy(true);
    try {
      const res = await fetch(imageUrl);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${slugify(eventName)}-${stripId.slice(0, 8)}-${format}.jpg`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      flashStatus("Downloaded ✨");
    } catch {
      setError("Download failed");
    } finally {
      setBusy(false);
    }
  }

  function handlePrint() {
    if (!imageUrl) return;
    // Open a blank window with just the image, kick off the print dialog
    // once it loads, and close the helper window when done. The system's
    // own print dialog handles printer + paper choice.
    const w = window.open("");
    if (!w) {
      setError("Couldn't open print window (popup blocked?)");
      return;
    }
    w.document.write(
      `<!doctype html><html><head><title>Print</title>` +
        `<style>@page { margin: 0 } html, body { margin: 0; padding: 0 } ` +
        `img { width: 100%; height: auto; display: block; }</style>` +
        `</head><body><img src="${imageUrl}" onload="setTimeout(()=>{window.print();window.close();},150)" /></body></html>`,
    );
    w.document.close();
    flashStatus("Sent to printer 🖨️");
  }

  async function handleSendDelivery(channel: "sms" | "email") {
    setError(null);
    const trimmed = recipient.trim();
    if (!trimmed) {
      setError("Enter a recipient");
      return;
    }
    const normalized = channel === "sms" ? normalizeUSPhone(trimmed) : trimmed;

    setBusy(true);
    try {
      const supabase = createClient();
      const { error: insertError } = await supabase.from("deliveries").insert({
        strip_id: stripId,
        channel,
        recipient: normalized,
      });
      if (insertError) throw new Error(insertError.message);
      flashStatus(channel === "sms" ? "Sending SMS… 💌" : "Sending email… 💌");
      setView("actions");
      setRecipient("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Send failed");
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete() {
    setBusy(true);
    try {
      const supabase = createClient();
      const paths = [composite2x6Path, composite4x6Path].filter(
        (p): p is string => p !== null,
      );
      if (paths.length) {
        await supabase.storage.from("composites").remove(paths);
      }
      const { error: deleteError } = await supabase
        .from("strips")
        .delete()
        .eq("id", stripId);
      if (deleteError) throw new Error(deleteError.message);
      onDeleted(stripId);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Delete failed");
      setBusy(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
      onClick={() => !busy && onClose()}
    >
      <div
        className="relative flex max-h-[92vh] w-full max-w-3xl flex-col overflow-hidden rounded-2xl bg-white shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <button
          onClick={onClose}
          disabled={busy}
          aria-label="Close"
          className="absolute right-3 top-3 z-10 flex h-9 w-9 items-center justify-center rounded-full bg-white/90 text-zinc-600 shadow ring-1 ring-zinc-200 backdrop-blur transition hover:text-zinc-900 disabled:opacity-50"
        >
          <svg width="18" height="18" viewBox="0 0 20 20" fill="currentColor" aria-hidden>
            <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
          </svg>
        </button>

        <div className="flex flex-1 items-center justify-center overflow-auto bg-zinc-100 p-6">
          {imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={imageUrl}
              alt=""
              className={
                format === "4x6"
                  ? "max-h-[62vh] w-auto rounded-lg shadow-md"
                  : "max-h-[78vh] w-auto rounded-lg shadow-md"
              }
            />
          ) : (
            <div className="flex h-40 items-center text-sm text-zinc-500">
              Image not available
            </div>
          )}
        </div>

        <div className="border-t border-zinc-200 bg-white px-6 py-4">
          <p className="mb-3 text-center text-xs text-zinc-500">
            Captured{" "}
            <time dateTime={createdAt}>
              {new Date(createdAt).toLocaleString(undefined, {
                weekday: "short",
                month: "short",
                day: "numeric",
                hour: "numeric",
                minute: "2-digit",
              })}
            </time>
          </p>
          {error ? (
            <div className="mb-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-200">
              {error}
            </div>
          ) : null}

          {view === "actions" ? (
            <div className="flex flex-wrap justify-center gap-2">
              <ActionBtn
                label="Email"
                tint="from-pink-500 to-rose-500"
                icon={<EmailIcon />}
                onClick={() => setView("email")}
                disabled={!imageUrl}
              />
              <ActionBtn
                label="SMS"
                tint="from-amber-500 to-orange-500"
                icon={<SmsIcon />}
                onClick={() => setView("sms")}
                disabled={!imageUrl}
              />
              <ActionBtn
                label="Open"
                tint="from-sky-500 to-blue-600"
                icon={<OpenIcon />}
                onClick={() =>
                  window.open(`/p/${stripId}`, "_blank", "noopener,noreferrer")
                }
              />
              <ActionBtn
                label="Download"
                tint="from-emerald-500 to-teal-500"
                icon={<DownloadIcon />}
                onClick={handleDownload}
                disabled={busy || !imageUrl}
              />
              <ActionBtn
                label="Print"
                tint="from-violet-500 to-purple-600"
                icon={<PrintIcon />}
                onClick={handlePrint}
                disabled={!imageUrl}
              />
              <ActionBtn
                label="Delete"
                tint="from-zinc-500 to-zinc-700"
                icon={<TrashIcon />}
                onClick={() => setView("confirm-delete")}
                disabled={busy}
              />
            </div>
          ) : null}

          {view === "email" || view === "sms" ? (
            <DeliveryForm
              channel={view}
              recipient={recipient}
              setRecipient={setRecipient}
              busy={busy}
              onCancel={() => {
                setRecipient("");
                setError(null);
                setView("actions");
              }}
              onSend={() => handleSendDelivery(view)}
            />
          ) : null}

          {view === "confirm-delete" ? (
            <div className="flex flex-col items-center gap-3 text-center">
              <p className="text-sm text-zinc-700">
                Delete this strip? It&apos;ll be removed from the gallery. This
                can&apos;t be undone.
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => setView("actions")}
                  disabled={busy}
                  className="rounded-full bg-zinc-100 px-4 py-2 text-sm font-semibold text-zinc-700 ring-1 ring-zinc-200 hover:bg-zinc-200 disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  onClick={handleDelete}
                  disabled={busy}
                  className="rounded-full bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-red-700 disabled:opacity-50"
                >
                  {busy ? "Deleting…" : "Delete"}
                </button>
              </div>
            </div>
          ) : null}

          {status ? (
            <p className="mt-2 text-center text-xs text-zinc-500" aria-live="polite">
              {status}
            </p>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function DeliveryForm({
  channel,
  recipient,
  setRecipient,
  busy,
  onCancel,
  onSend,
}: {
  channel: "sms" | "email";
  recipient: string;
  setRecipient: (v: string) => void;
  busy: boolean;
  onCancel: () => void;
  onSend: () => void;
}) {
  return (
    <div className="flex flex-col gap-3">
      <label className="text-sm font-medium text-zinc-700">
        {channel === "email" ? "Email address" : "Phone number"}
        <input
          autoFocus
          type={channel === "email" ? "email" : "tel"}
          value={recipient}
          onChange={(e) => setRecipient(e.target.value)}
          placeholder={channel === "email" ? "name@example.com" : "408 123 4567"}
          className="mt-1 w-full rounded-lg border-0 px-3 py-2 ring-1 ring-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-600"
          disabled={busy}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !busy) onSend();
          }}
        />
      </label>
      <div className="flex justify-end gap-2">
        <button
          onClick={onCancel}
          disabled={busy}
          className="rounded-full bg-zinc-100 px-4 py-2 text-sm font-semibold text-zinc-700 ring-1 ring-zinc-200 hover:bg-zinc-200 disabled:opacity-50"
        >
          Cancel
        </button>
        <button
          onClick={onSend}
          disabled={busy || !recipient.trim()}
          className="ig-gradient rounded-full px-5 py-2 text-sm font-semibold text-white shadow disabled:opacity-50"
        >
          {busy ? "Sending…" : "Send"}
        </button>
      </div>
    </div>
  );
}

function ActionBtn({
  label,
  tint,
  icon,
  onClick,
  disabled,
}: {
  label: string;
  tint: string;
  icon: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="flex flex-col items-center gap-1.5 disabled:opacity-50"
    >
      <span
        className={`flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br ${tint} text-white shadow-md`}
      >
        {icon}
      </span>
      <span className="text-xs font-semibold text-zinc-700">{label}</span>
    </button>
  );
}

function normalizeUSPhone(raw: string): string {
  if (raw.startsWith("+")) return "+" + raw.slice(1).replace(/\D/g, "");
  return "+1" + raw.replace(/\D/g, "");
}

function slugify(input: string): string {
  return (
    input
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 40) || "photoboot"
  );
}

function EmailIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M2.5 5.5A1.5 1.5 0 0 1 4 4h12a1.5 1.5 0 0 1 1.5 1.5v9A1.5 1.5 0 0 1 16 16H4a1.5 1.5 0 0 1-1.5-1.5v-9Zm1.747-.083L10 9.583l5.753-4.166A.5.5 0 0 0 15.5 5H4.5a.5.5 0 0 0-.253.417Zm11.753 1.25L10.293 11a.5.5 0 0 1-.586 0L4 6.667V14.5a.5.5 0 0 0 .5.5h11a.5.5 0 0 0 .5-.5V6.667Z" />
    </svg>
  );
}

function SmsIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M3.5 3A1.5 1.5 0 0 0 2 4.5v9A1.5 1.5 0 0 0 3.5 15h4l2.5 2.5L12.5 15h4a1.5 1.5 0 0 0 1.5-1.5v-9A1.5 1.5 0 0 0 16.5 3h-13Z" />
    </svg>
  );
}

function OpenIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M11 3.75A.75.75 0 0 1 11.75 3h4.5a.75.75 0 0 1 .75.75v4.5a.75.75 0 0 1-1.5 0V5.56l-5.97 5.97a.75.75 0 1 1-1.06-1.06L14.44 4.5h-2.69a.75.75 0 0 1-.75-.75Z" />
      <path d="M4 6.75A1.75 1.75 0 0 1 5.75 5H9a.75.75 0 0 1 0 1.5H5.75a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25V11a.75.75 0 0 1 1.5 0v3.25A1.75 1.75 0 0 1 13.25 16h-7.5A1.75 1.75 0 0 1 4 14.25v-7.5Z" />
    </svg>
  );
}

function DownloadIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M10 3a.75.75 0 0 1 .75.75v8.69l2.72-2.72a.75.75 0 1 1 1.06 1.06l-4 4a.75.75 0 0 1-1.06 0l-4-4a.75.75 0 1 1 1.06-1.06l2.72 2.72V3.75A.75.75 0 0 1 10 3Z" />
      <path d="M3.75 14a.75.75 0 0 1 .75.75v1.5c0 .414.336.75.75.75h9.5a.75.75 0 0 0 .75-.75v-1.5a.75.75 0 0 1 1.5 0v1.5A2.25 2.25 0 0 1 14.75 18.5h-9.5A2.25 2.25 0 0 1 3 16.25v-1.5a.75.75 0 0 1 .75-.75Z" />
    </svg>
  );
}

function PrintIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M6 3.5A1.5 1.5 0 0 1 7.5 2h5A1.5 1.5 0 0 1 14 3.5V6h.5A2.5 2.5 0 0 1 17 8.5v4A1.5 1.5 0 0 1 15.5 14H14v2a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1v-2H4.5A1.5 1.5 0 0 1 3 12.5v-4A2.5 2.5 0 0 1 5.5 6H6V3.5Zm2 0V6h4V3.5h-4ZM7 12h6v3H7v-3Z" />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M8.5 2a1 1 0 0 0-1 1V4H4.75a.75.75 0 0 0 0 1.5H5l.69 10.34A2 2 0 0 0 7.685 18h4.63a2 2 0 0 0 1.995-2.16L15 5.5h.25a.75.75 0 0 0 0-1.5H12.5V3a1 1 0 0 0-1-1h-3Zm.5 2V3h2v1h-2Zm-1.5 4.25a.75.75 0 0 1 .75.75v6a.75.75 0 0 1-1.5 0v-6a.75.75 0 0 1 .75-.75Zm5 0a.75.75 0 0 1 .75.75v6a.75.75 0 0 1-1.5 0v-6a.75.75 0 0 1 .75-.75Z" />
    </svg>
  );
}
