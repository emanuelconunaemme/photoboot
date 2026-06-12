"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export interface StripWithUrl {
  id: string;
  composite_path: string;
  created_at: string;
  signed_url: string | null;
}

const SIGNED_URL_TTL_SECONDS = 3600;

export function StripGrid({
  eventId,
  initial,
}: {
  eventId: string;
  initial: StripWithUrl[];
}) {
  const [strips, setStrips] = useState<StripWithUrl[]>(initial);

  useEffect(() => {
    const supabase = createClient();

    async function loadSignedUrl(compositePath: string): Promise<string | null> {
      const { data } = await supabase.storage
        .from("composites")
        .createSignedUrl(compositePath, SIGNED_URL_TTL_SECONDS);
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
            composite_path: string | null;
            created_at: string;
          };
          if (!row.composite_path) return;

          const signed_url = await loadSignedUrl(row.composite_path);
          setStrips((prev) => {
            const without = prev.filter((s) => s.id !== row.id);
            return [
              {
                id: row.id,
                composite_path: row.composite_path as string,
                created_at: row.created_at,
                signed_url,
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

  if (strips.length === 0) {
    return (
      <div className="mt-4 flex flex-col items-center gap-3 rounded-2xl border border-dashed border-zinc-300 bg-white p-12 text-center">
        <div className="ig-gradient flex h-14 w-14 items-center justify-center rounded-full text-2xl text-white shadow-md">
          ✨
        </div>
        <p className="ig-gradient-text text-lg font-semibold">
          No strips yet
        </p>
        <p className="text-sm text-zinc-500">
          The first one shows up here as soon as it&apos;s captured on the iPad.
        </p>
      </div>
    );
  }

  return (
    <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
      {strips.map((strip) => (
        <div
          key={strip.id}
          className="ig-gradient aspect-[3/5] rounded-2xl p-[2px] shadow-sm transition hover:shadow-md"
        >
          <div className="h-full w-full overflow-hidden rounded-[14px] bg-zinc-200">
            {strip.signed_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={strip.signed_url}
                alt=""
                className="h-full w-full object-cover transition hover:scale-[1.02]"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-xs text-zinc-400">
                Loading…
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
