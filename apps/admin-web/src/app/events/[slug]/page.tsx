import Link from "next/link";
import { notFound } from "next/navigation";
import { Header } from "@/components/Header";
import { createClient } from "@/lib/supabase/server";
import type { EventRow, PhotoRow } from "@/lib/database";
import { PhotoGrid, type PhotoWithUrl } from "./PhotoGrid";

const SIGNED_URL_TTL_SECONDS = 3600;

export default async function EventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const supabase = await createClient();

  const { data: event } = await supabase
    .from("events")
    .select("id, name, slug, status, gphotos_share_url")
    .eq("slug", slug)
    .maybeSingle<Pick<EventRow, "id" | "name" | "slug" | "status" | "gphotos_share_url">>();

  if (!event) notFound();

  const { data: photos } = await supabase
    .from("photos")
    .select("id, event_id, status, capture_mode, storage_path, taken_at, ready_at")
    .eq("event_id", event.id)
    .order("taken_at", { ascending: false })
    .returns<Pick<PhotoRow, "id" | "event_id" | "status" | "capture_mode" | "storage_path" | "taken_at" | "ready_at">[]>();

  const readyPhotos = (photos ?? []).filter(
    (p): p is typeof p & { storage_path: string } =>
      p.status === "ready" && Boolean(p.storage_path),
  );

  const signed = readyPhotos.length
    ? await supabase.storage
        .from("photos")
        .createSignedUrls(
          readyPhotos.map((p) => p.storage_path),
          SIGNED_URL_TTL_SECONDS,
        )
    : { data: [], error: null };

  const urlByPath = new Map(
    (signed.data ?? []).map((entry) => [entry.path ?? "", entry.signedUrl]),
  );

  const initial: PhotoWithUrl[] = readyPhotos.map((p) => ({
    id: p.id,
    storage_path: p.storage_path,
    taken_at: p.taken_at,
    capture_mode: p.capture_mode,
    signed_url: urlByPath.get(p.storage_path) ?? null,
  }));

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <Link href="/" className="text-sm text-zinc-500 hover:text-zinc-900">
          ← All events
        </Link>

        <div className="mt-4 flex items-end justify-between">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">
              {event.name}
            </h1>
            <p className="text-sm text-zinc-500">
              {event.slug} · {event.status}
            </p>
          </div>
        </div>

        <section className="mt-8">
          <h2 className="text-sm font-medium text-zinc-700">Photos</h2>
          <PhotoGrid eventId={event.id} initial={initial} />
        </section>
      </main>
    </>
  );
}
