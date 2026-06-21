"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { StripFormat } from "@/lib/database";
import { StripDetail } from "./StripDetail";

export interface StripWithUrls {
  id: string;
  composite_2x6_path: string | null;
  composite_4x6_path: string | null;
  url_2x6: string | null;
  url_4x6: string | null;
  created_at: string;
}

const SIGNED_URL_TTL_SECONDS = 3600;

export function StripGrid({
  eventId,
  eventName,
  initial,
}: {
  eventId: string;
  eventName: string;
  initial: StripWithUrls[];
}) {
  const [strips, setStrips] = useState<StripWithUrls[]>(initial);
  const [format, setFormat] = useState<StripFormat>("4x6");
  const [activeStripId, setActiveStripId] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();

    async function loadSignedUrl(path: string): Promise<string | null> {
      const { data } = await supabase.storage
        .from("composites")
        .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
      return data?.signedUrl ?? null;
    }

    const channel = supabase
      .channel(`event-${eventId}-strips`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "strips",
          filter: `event_id=eq.${eventId}`,
        },
        async (payload) => {
          if (payload.eventType === "DELETE") {
            const oldRow = payload.old as { id: string };
            setStrips((prev) => prev.filter((s) => s.id !== oldRow.id));
            return;
          }

          const row = payload.new as {
            id: string;
            composite_2x6_path: string | null;
            composite_4x6_path: string | null;
            created_at: string;
          };
          if (!row.composite_2x6_path && !row.composite_4x6_path) return;

          const [url_2x6, url_4x6] = await Promise.all([
            row.composite_2x6_path
              ? loadSignedUrl(row.composite_2x6_path)
              : Promise.resolve(null),
            row.composite_4x6_path
              ? loadSignedUrl(row.composite_4x6_path)
              : Promise.resolve(null),
          ]);

          setStrips((prev) => {
            const without = prev.filter((s) => s.id !== row.id);
            return [
              {
                id: row.id,
                composite_2x6_path: row.composite_2x6_path,
                composite_4x6_path: row.composite_4x6_path,
                url_2x6,
                url_4x6,
                created_at: row.created_at,
              },
              ...without,
            ];
          });
        },
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [eventId]);

  return (
    <>
      <div className="mt-3 flex items-center gap-2">
        <FormatPill
          value="4x6"
          active={format === "4x6"}
          onSelect={() => setFormat("4x6")}
        />
        <FormatPill
          value="2x6"
          active={format === "2x6"}
          onSelect={() => setFormat("2x6")}
        />
      </div>

      {strips.length === 0 ? (
        <div className="mt-4 flex flex-col items-center gap-3 rounded-2xl border border-dashed border-zinc-300 bg-white p-12 text-center">
          <div className="ig-gradient flex h-14 w-14 items-center justify-center rounded-full text-2xl text-white shadow-md">
            ✨
          </div>
          <p className="ig-gradient-text text-lg font-semibold">No strips yet</p>
          <p className="text-sm text-zinc-500">
            The first one shows up here as soon as it&apos;s captured on the
            iPad.
          </p>
        </div>
      ) : (
        <div
          className={
            format === "4x6"
              ? "mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
              : "mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5"
          }
        >
          {strips.map((strip) => {
            const url = format === "4x6" ? strip.url_4x6 : strip.url_2x6;
            const aspect = format === "4x6" ? "aspect-[3/2]" : "aspect-[1/3]";
            return (
              <div key={strip.id} className="flex flex-col gap-1.5">
                <button
                  onClick={() => url && setActiveStripId(strip.id)}
                  disabled={!url}
                  className={`ig-gradient ${aspect} rounded-2xl p-[2px] shadow-sm transition hover:shadow-md disabled:cursor-default`}
                >
                  <div className="h-full w-full overflow-hidden rounded-[14px] bg-zinc-200">
                    {url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={url}
                        alt=""
                        className="h-full w-full object-cover transition hover:scale-[1.02]"
                      />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center text-xs text-zinc-400">
                        {format === "4x6"
                          ? strip.composite_4x6_path
                            ? "Loading…"
                            : "No 4×6"
                          : strip.composite_2x6_path
                            ? "Loading…"
                            : "No 2×6"}
                      </div>
                    )}
                  </div>
                </button>
                <time
                  dateTime={strip.created_at}
                  title={new Date(strip.created_at).toLocaleString()}
                  className="text-center text-xs text-zinc-500"
                >
                  {formatStripTimestamp(strip.created_at)}
                </time>
              </div>
            );
          })}
        </div>
      )}

      {activeStripId
        ? (() => {
            const strip = strips.find((s) => s.id === activeStripId);
            if (!strip) return null;
            const url = format === "4x6" ? strip.url_4x6 : strip.url_2x6;
            return (
              <StripDetail
                key={strip.id}
                open
                onClose={() => setActiveStripId(null)}
                onDeleted={(id) =>
                  setStrips((prev) => prev.filter((s) => s.id !== id))
                }
                stripId={strip.id}
                composite2x6Path={strip.composite_2x6_path}
                composite4x6Path={strip.composite_4x6_path}
                imageUrl={url}
                format={format}
                eventName={eventName}
                createdAt={strip.created_at}
              />
            );
          })()
        : null}
    </>
  );
}

function formatStripTimestamp(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const sameDay =
    d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate();
  const sameYear = d.getFullYear() === now.getFullYear();
  if (sameDay) {
    return d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  }
  if (sameYear) {
    return d.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  }
  return d.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

function FormatPill({
  value,
  active,
  onSelect,
}: {
  value: StripFormat;
  active: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      onClick={onSelect}
      className={
        active
          ? "ig-gradient rounded-full px-3 py-1 text-xs font-semibold text-white shadow-sm"
          : "rounded-full bg-white px-3 py-1 text-xs font-semibold text-zinc-600 ring-1 ring-zinc-200 hover:bg-zinc-50"
      }
    >
      {value}
    </button>
  );
}
