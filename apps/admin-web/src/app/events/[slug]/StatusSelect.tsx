"use client";

import { useState, useTransition } from "react";
import type { EventStatus } from "@/lib/database";
import { updateEventStatus } from "./status-actions";

const STATUS_OPTIONS: readonly EventStatus[] = [
  "draft",
  "upcoming",
  "live",
  "done",
];

const STATUS_CLASSES: Record<EventStatus, string> = {
  draft: "bg-zinc-100 text-zinc-600 ring-zinc-200",
  upcoming: "bg-sky-100 text-sky-700 ring-sky-200",
  live: "ig-gradient text-white ring-transparent",
  done: "bg-zinc-200 text-zinc-500 ring-zinc-300",
};

export function StatusSelect({
  eventId,
  status: initialStatus,
}: {
  eventId: string;
  status: EventStatus;
}) {
  const [status, setStatus] = useState<EventStatus>(initialStatus);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function onChange(next: EventStatus) {
    const previous = status;
    setStatus(next);
    setError(null);
    startTransition(async () => {
      const result = await updateEventStatus(eventId, next);
      if (result.error) {
        setStatus(previous);
        setError(result.error);
      }
    });
  }

  return (
    <span className="inline-flex items-center gap-2">
      <span className="relative inline-flex">
        <select
          value={status}
          disabled={isPending}
          onChange={(e) => onChange(e.target.value as EventStatus)}
          className={`cursor-pointer appearance-none rounded-full py-0.5 pl-2.5 pr-6 text-xs font-semibold ring-1 transition disabled:opacity-60 ${STATUS_CLASSES[status]}`}
          aria-label="Event status"
        >
          {STATUS_OPTIONS.map((option) => (
            <option key={option} value={option} className="bg-white text-zinc-700">
              {option}
            </option>
          ))}
        </select>
        <span className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 text-[10px]">
          ▾
        </span>
      </span>
      {error ? <span className="text-xs text-red-600">{error}</span> : null}
    </span>
  );
}
