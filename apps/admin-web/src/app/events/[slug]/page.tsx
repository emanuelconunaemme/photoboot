import Link from "next/link";
import { notFound } from "next/navigation";
import { Header } from "@/components/Header";
import { createClient } from "@/lib/supabase/server";
import type { EventRow, PhotoRow, StripRow } from "@/lib/database";
import { PhotoGrid, type PhotoWithUrl } from "./PhotoGrid";
import { StripGrid, type StripWithUrls } from "./StripGrid";

const SIGNED_URL_TTL_SECONDS = 3600;

const STATUS_CLASSES: Record<string, string> = {
  draft: "bg-zinc-100 text-zinc-600 ring-zinc-200",
  live: "ig-gradient text-white ring-transparent",
  archived: "bg-zinc-200 text-zinc-500 ring-zinc-300",
};

export default async function EventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const supabase = await createClient();

  const { data: event } = await supabase
    .from("events")
    .select(
      "id, name, slug, status, gphotos_share_url, description, event_date, primary_color, secondary_color, background_2x6_path, background_4x6_path, updated_at",
    )
    .eq("slug", slug)
    .maybeSingle<
      Pick<
        EventRow,
        | "id"
        | "name"
        | "slug"
        | "status"
        | "gphotos_share_url"
        | "description"
        | "event_date"
        | "primary_color"
        | "secondary_color"
        | "background_2x6_path"
        | "background_4x6_path"
        | "updated_at"
      >
    >();

  if (!event) notFound();

  const { data: strips } = await supabase
    .from("strips")
    .select("id, event_id, composite_2x6_path, composite_4x6_path, created_at")
    .eq("event_id", event.id)
    .order("created_at", { ascending: false })
    .returns<Pick<StripRow, "id" | "event_id" | "composite_2x6_path" | "composite_4x6_path" | "created_at">[]>();

  const readyStrips = (strips ?? []).filter(
    (s) => s.composite_2x6_path || s.composite_4x6_path,
  );

  const allCompositePaths = readyStrips.flatMap((s) =>
    [s.composite_2x6_path, s.composite_4x6_path].filter(
      (p): p is string => p !== null,
    ),
  );

  const stripSigned = allCompositePaths.length
    ? await supabase.storage
        .from("composites")
        .createSignedUrls(allCompositePaths, SIGNED_URL_TTL_SECONDS)
    : { data: [], error: null };

  const stripUrlByPath = new Map(
    (stripSigned.data ?? []).map((entry) => [entry.path ?? "", entry.signedUrl]),
  );

  const initialStrips: StripWithUrls[] = readyStrips.map((s) => ({
    id: s.id,
    composite_2x6_path: s.composite_2x6_path,
    composite_4x6_path: s.composite_4x6_path,
    url_2x6: s.composite_2x6_path ? stripUrlByPath.get(s.composite_2x6_path) ?? null : null,
    url_4x6: s.composite_4x6_path ? stripUrlByPath.get(s.composite_4x6_path) ?? null : null,
    created_at: s.created_at,
  }));

  // Raw photos
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

  const photoSigned = readyPhotos.length
    ? await supabase.storage
        .from("photos")
        .createSignedUrls(
          readyPhotos.map((p) => p.storage_path),
          SIGNED_URL_TTL_SECONDS,
        )
    : { data: [], error: null };

  const photoUrlByPath = new Map(
    (photoSigned.data ?? []).map((entry) => [entry.path ?? "", entry.signedUrl]),
  );

  const initialPhotos: PhotoWithUrl[] = readyPhotos.map((p) => ({
    id: p.id,
    storage_path: p.storage_path,
    taken_at: p.taken_at,
    capture_mode: p.capture_mode,
    signed_url: photoUrlByPath.get(p.storage_path) ?? null,
  }));

  // Background image public URLs (templates bucket is public-read).
  // Append updated_at as a cache-buster: same path = same URL, so the
  // browser would otherwise hold the old image forever after an edit.
  const version = encodeURIComponent(event.updated_at);
  const bg2x6Url = event.background_2x6_path
    ? `${supabase.storage.from("templates").getPublicUrl(event.background_2x6_path).data.publicUrl}?v=${version}`
    : null;
  const bg4x6Url = event.background_4x6_path
    ? `${supabase.storage.from("templates").getPublicUrl(event.background_4x6_path).data.publicUrl}?v=${version}`
    : null;

  const statusClass = STATUS_CLASSES[event.status] ?? STATUS_CLASSES.draft;
  const formattedDate = event.event_date
    ? new Date(event.event_date + "T00:00:00Z").toLocaleDateString(undefined, {
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric",
        timeZone: "UTC",
      })
    : null;

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <Link
          href="/"
          className="text-ig-pink hover:text-ig-purple text-sm font-medium transition"
        >
          ← All events
        </Link>

        <div className="mt-5 flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <h1 className="ig-gradient-text text-4xl font-bold tracking-tight">
              {event.name}
            </h1>
            <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-zinc-500">
              <span className="font-mono">{event.slug}</span>
              <span>·</span>
              <span
                className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ${statusClass}`}
              >
                {event.status}
              </span>
              {formattedDate ? (
                <>
                  <span>·</span>
                  <span>{formattedDate}</span>
                </>
              ) : null}
            </div>
            {event.description ? (
              <p className="mt-3 max-w-xl text-sm text-zinc-600">
                {event.description}
              </p>
            ) : null}
          </div>

          <div className="flex flex-col items-end gap-3">
            <Link
              href={`/events/${event.slug}/edit`}
              className="ig-gradient inline-flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-sm font-semibold text-white shadow-sm transition hover:opacity-90"
            >
              Edit event
            </Link>
            <div className="flex items-center gap-2">
              <ColorSwatch label="Primary" hex={event.primary_color} />
              <ColorSwatch label="Secondary" hex={event.secondary_color} />
            </div>
          </div>
        </div>

        {bg2x6Url || bg4x6Url ? (
          <section className="mt-8">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-500">
              Backgrounds
            </h2>
            <div className="mt-3 flex flex-wrap items-end gap-6">
              {bg2x6Url ? (
                <BackgroundPreview label="2×6" url={bg2x6Url} aspectRatio="1/3" />
              ) : null}
              {bg4x6Url ? (
                <BackgroundPreview label="4×6" url={bg4x6Url} aspectRatio="3/2" />
              ) : null}
            </div>
          </section>
        ) : null}

        <section className="mt-10">
          <div className="flex items-baseline justify-between">
            <h2 className="text-xl font-semibold tracking-tight">Strips</h2>
            <span className="text-xs text-zinc-500">
              {initialStrips.length}{" "}
              {initialStrips.length === 1 ? "strip" : "strips"}
            </span>
          </div>
          <StripGrid eventId={event.id} eventName={event.name} initial={initialStrips} />
        </section>

        <section className="mt-12">
          <details className="group">
            <summary className="flex cursor-pointer list-none items-baseline justify-between">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-500 group-open:text-zinc-700">
                Raw photos ({initialPhotos.length})
              </h2>
              <span className="text-xs text-zinc-400 group-open:hidden">
                Show
              </span>
              <span className="hidden text-xs text-zinc-400 group-open:inline">
                Hide
              </span>
            </summary>
            <div className="mt-3">
              <PhotoGrid eventId={event.id} initial={initialPhotos} />
            </div>
          </details>
        </section>
      </main>
    </>
  );
}

function ColorSwatch({ label, hex }: { label: string; hex: string }) {
  return (
    <div className="flex items-center gap-2 rounded-full bg-white px-2.5 py-1 ring-1 ring-zinc-200">
      <span
        className="h-4 w-4 rounded-full ring-1 ring-black/10"
        style={{ backgroundColor: hex }}
      />
      <span className="text-xs text-zinc-600">
        <span className="text-zinc-400">{label}</span>{" "}
        <span className="font-mono">{hex}</span>
      </span>
    </div>
  );
}

function BackgroundPreview({
  label,
  url,
  aspectRatio,
}: {
  label: string;
  url: string;
  aspectRatio: string; // "1/3" or "3/2" — inline style so we can mix orientations
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
        {label}
      </p>
      <div
        className="h-40 overflow-hidden rounded-lg bg-zinc-100 ring-1 ring-zinc-200"
        style={{ aspectRatio }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={url} alt={`${label} background`} className="h-full w-full object-cover" />
      </div>
    </div>
  );
}
