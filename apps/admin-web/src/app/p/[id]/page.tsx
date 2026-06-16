import { notFound } from "next/navigation";
import Link from "next/link";
import { createClient } from "@supabase/supabase-js";
import { StripActions } from "./StripActions";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SIGNED_URL_TTL_SECONDS = 3600;

interface EventRef {
  name: string;
  event_date: string | null;
}

interface StripWithEvent {
  id: string;
  composite_2x6_path: string | null;
  composite_4x6_path: string | null;
  events: EventRef | EventRef[] | null;
}

export default async function PublicStripPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    return (
      <main className="flex min-h-screen items-center justify-center p-8 text-zinc-600">
        Server misconfigured
      </main>
    );
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: strip } = await supabase
    .from("strips")
    .select("id, composite_2x6_path, composite_4x6_path, events(name, event_date)")
    .eq("id", id)
    .maybeSingle<StripWithEvent>();

  if (!strip || (!strip.composite_2x6_path && !strip.composite_4x6_path)) {
    notFound();
  }

  const paths = [strip.composite_2x6_path, strip.composite_4x6_path].filter(
    (p): p is string => p !== null,
  );
  const { data: signed } = await supabase.storage
    .from("composites")
    .createSignedUrls(paths, SIGNED_URL_TTL_SECONDS);
  const urlByPath = new Map(
    (signed ?? []).map((entry) => [entry.path ?? "", entry.signedUrl]),
  );

  const url2x6 = strip.composite_2x6_path
    ? urlByPath.get(strip.composite_2x6_path) ?? null
    : null;
  const url4x6 = strip.composite_4x6_path
    ? urlByPath.get(strip.composite_4x6_path) ?? null
    : null;

  if (!url2x6 && !url4x6) notFound();

  const event = Array.isArray(strip.events) ? strip.events[0] : strip.events;
  const eventName = event?.name ?? "your event";
  const eventDate = event?.event_date
    ? new Date(event.event_date + "T00:00:00Z").toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
        timeZone: "UTC",
      })
    : null;

  const slug = slugify(eventName);
  const shortId = id.slice(0, 8);

  return (
    <main className="flex min-h-screen flex-col items-center bg-zinc-50 px-4 py-10">
      <Link
        href="/"
        className="ig-gradient-text mb-8 text-lg font-bold tracking-tight"
      >
        Photoboot ✨
      </Link>

      <h1 className="ig-gradient-text text-center text-3xl font-bold tracking-tight">
        {eventName}
      </h1>
      {eventDate ? (
        <p className="mt-1 text-sm text-zinc-500">{eventDate}</p>
      ) : null}

      <p className="mt-2 text-sm text-zinc-500">
        Pick the format you want to download or share.
      </p>

      <div className="mt-8 flex w-full max-w-5xl flex-col items-center gap-10 md:flex-row md:items-start md:justify-center">
        {url4x6 ? (
          <FormatCard
            label="4×6 print"
            url={url4x6}
            aspect="aspect-[3/2]"
            maxHeightClass="max-h-[60vh]"
            filename={`${slug}-${shortId}-4x6.jpg`}
            title={`Your 4×6 from ${eventName}`}
          />
        ) : null}
        {url2x6 ? (
          <FormatCard
            label="2×6 strip"
            url={url2x6}
            aspect="aspect-[1/3]"
            maxHeightClass="max-h-[70vh]"
            filename={`${slug}-${shortId}-2x6.jpg`}
            title={`Your 2×6 from ${eventName}`}
          />
        ) : null}
      </div>

      <p className="mt-12 text-xs text-zinc-400">Made with Photoboot</p>
    </main>
  );
}

function FormatCard({
  label,
  url,
  aspect,
  maxHeightClass,
  filename,
  title,
}: {
  label: string;
  url: string;
  aspect: string;
  maxHeightClass: string;
  filename: string;
  title: string;
}) {
  return (
    <div className="flex flex-col items-center gap-4">
      <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
        {label}
      </p>
      <div className="ig-gradient rounded-3xl p-[3px] shadow-xl">
        <div className={`${maxHeightClass} ${aspect} overflow-hidden rounded-[20px] bg-white`}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={url}
            alt={title}
            className="h-full w-full object-contain"
          />
        </div>
      </div>
      <StripActions
        imageUrl={url}
        filename={filename}
        title={title}
        size="small"
      />
    </div>
  );
}

function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40) || "photoboot";
}
