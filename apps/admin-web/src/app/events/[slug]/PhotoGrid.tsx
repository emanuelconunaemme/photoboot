"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export interface PhotoWithUrl {
  id: string;
  storage_path: string;
  taken_at: string;
  capture_mode: string;
  signed_url: string | null;
}

const SIGNED_URL_TTL_SECONDS = 3600;

export function PhotoGrid({
  eventId,
  initial,
}: {
  eventId: string;
  initial: PhotoWithUrl[];
}) {
  const [photos, setPhotos] = useState<PhotoWithUrl[]>(initial);

  useEffect(() => {
    const supabase = createClient();

    async function loadSignedUrl(storagePath: string): Promise<string | null> {
      const { data } = await supabase.storage
        .from("photos")
        .createSignedUrl(storagePath, SIGNED_URL_TTL_SECONDS);
      return data?.signedUrl ?? null;
    }

    const channel = supabase
      .channel(`event-${eventId}-photos`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "photos",
          filter: `event_id=eq.${eventId}`,
        },
        async (payload) => {
          const row = payload.new as {
            id: string;
            status: string;
            storage_path: string | null;
            taken_at: string;
            capture_mode: string;
          };

          if (row.status !== "ready" || !row.storage_path) return;

          const signed_url = await loadSignedUrl(row.storage_path);
          setPhotos((prev) => {
            const without = prev.filter((p) => p.id !== row.id);
            return [
              {
                id: row.id,
                storage_path: row.storage_path as string,
                taken_at: row.taken_at,
                capture_mode: row.capture_mode,
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

  if (photos.length === 0) {
    return (
      <div className="mt-3 rounded-xl border border-dashed border-zinc-300 bg-white p-10 text-center text-sm text-zinc-500">
        No photos yet. Capture one on the iPad — it&apos;ll appear here in real time.
      </div>
    );
  }

  return (
    <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
      {photos.map((photo) => (
        <div
          key={photo.id}
          className="aspect-[3/4] overflow-hidden rounded-lg bg-zinc-200 ring-1 ring-zinc-200"
        >
          {photo.signed_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={photo.signed_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center text-xs text-zinc-400">
              Loading…
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
