"use client";

import { useState } from "react";

interface Props {
  imageUrl: string;
  filename: string;
  title: string;
  size?: "small" | "default";
}

export function StripActions({ imageUrl, filename, title, size = "default" }: Props) {
  const [status, setStatus] = useState<string | null>(null);
  const [busy, setBusy] = useState<"download" | "share" | null>(null);

  function flashStatus(message: string) {
    setStatus(message);
    setTimeout(() => setStatus(null), 2500);
  }

  async function handleDownload() {
    setBusy("download");
    try {
      const res = await fetch(imageUrl);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      flashStatus("Downloaded ✨");
    } catch {
      flashStatus("Download failed");
    } finally {
      setBusy(null);
    }
  }

  async function handleShare() {
    setBusy("share");
    try {
      try {
        const res = await fetch(imageUrl);
        const blob = await res.blob();
        const file = new File([blob], filename, { type: blob.type });
        if (navigator.canShare?.({ files: [file] })) {
          await navigator.share({ files: [file], title });
          flashStatus("Shared!");
          return;
        }
      } catch {
        // file share failed; fall through
      }

      if (navigator.share) {
        await navigator.share({ title, url: window.location.href });
        flashStatus("Shared!");
        return;
      }

      await navigator.clipboard.writeText(window.location.href);
      flashStatus("Link copied 📋");
    } catch {
      // cancelled
    } finally {
      setBusy(null);
    }
  }

  const padding = size === "small" ? "px-4 py-2" : "px-6 py-3";
  const textSize = size === "small" ? "text-xs" : "text-sm";

  return (
    <div className="flex flex-col items-center gap-2">
      <div className="flex flex-wrap justify-center gap-2">
        <button
          onClick={handleDownload}
          disabled={busy !== null}
          className={`ig-gradient flex items-center gap-2 rounded-full font-semibold text-white shadow-md transition hover:opacity-90 disabled:opacity-60 ${padding} ${textSize}`}
        >
          <DownloadIcon className="h-4 w-4" />
          {busy === "download" ? "…" : "Download"}
        </button>
        <button
          onClick={handleShare}
          disabled={busy !== null}
          className={`flex items-center gap-2 rounded-full bg-white font-semibold text-zinc-900 shadow-md ring-1 ring-zinc-200 transition hover:bg-zinc-50 disabled:opacity-60 ${padding} ${textSize}`}
        >
          <ShareIcon className="h-4 w-4" />
          {busy === "share" ? "…" : "Share"}
        </button>
      </div>
      {status ? (
        <p className="text-xs text-zinc-500" aria-live="polite">
          {status}
        </p>
      ) : null}
    </div>
  );
}

function DownloadIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M10 3a.75.75 0 0 1 .75.75v8.69l2.72-2.72a.75.75 0 1 1 1.06 1.06l-4 4a.75.75 0 0 1-1.06 0l-4-4a.75.75 0 1 1 1.06-1.06l2.72 2.72V3.75A.75.75 0 0 1 10 3Z" />
      <path d="M3.75 14a.75.75 0 0 1 .75.75v1.5c0 .414.336.75.75.75h9.5a.75.75 0 0 0 .75-.75v-1.5a.75.75 0 0 1 1.5 0v1.5A2.25 2.25 0 0 1 14.75 18.5h-9.5A2.25 2.25 0 0 1 3 16.25v-1.5a.75.75 0 0 1 .75-.75Z" />
    </svg>
  );
}

function ShareIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 20 20" fill="currentColor" aria-hidden>
      <path d="M13 4.5a2.5 2.5 0 1 1 .39 1.34l-5.07 2.92a2.5 2.5 0 0 1 0 2.48l5.07 2.92a2.5 2.5 0 1 1-.74 1.3l-5.08-2.93a2.5 2.5 0 1 1 0-3.06l5.08-2.93A2.5 2.5 0 0 1 13 4.5Z" />
    </svg>
  );
}
