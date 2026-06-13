import { notFound } from "next/navigation";
import Link from "next/link";
import { createClient } from "@supabase/supabase-js";
import { StripActions } from "./StripActions";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SIGNED_URL_TTL_SECONDS = 3600;

interface EventRef {
  name: string;
  event_date: string | null;
  primary_color: string;
  secondary_color: string;
}

interface StripWithEvent {
  id: string;
  composite_path: string | null;
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
    .select("id, composite_path, events(name, event_date, primary_color, secondary_color)")
    .eq("id", id)
    .maybeSingle<StripWithEvent>();

  if (!strip?.composite_path) notFound();

  const { data: signed } = await supabase.storage
    .from("composites")
    .createSignedUrl(strip.composite_path, SIGNED_URL_TTL_SECONDS);

  if (!signed?.signedUrl) notFound();

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
  const filename = makeFilename(eventName, id);

  return (
    <main className="flex min-h-screen flex-col items-center bg-zinc-50 px-4 py-10">
      <Link
        href="/"
        className="ig-gradient-text mb-8 text-lg font-bold tracking-tight"
      >
        Photoboot ✨
      </Link>

      <div className="ig-gradient rounded-3xl p-[3px] shadow-xl">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={signed.signedUrl}
          alt={`Strip from ${eventName}`}
          className="block max-h-[70vh] w-auto rounded-[20px] bg-white"
        />
      </div>

      <h1 className="ig-gradient-text mt-8 text-center text-3xl font-bold tracking-tight">
        {eventName}
      </h1>
      {eventDate ? (
        <p className="mt-1 text-sm text-zinc-500">{eventDate}</p>
      ) : null}

      <StripActions
        imageUrl={signed.signedUrl}
        filename={filename}
        title={`Your photo from ${eventName}`}
      />

      <p className="mt-12 text-xs text-zinc-400">Made with Photoboot</p>
    </main>
  );
}

function makeFilename(eventName: string, id: string): string {
  const slug = eventName
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
  return `${slug || "photoboot"}-${id.slice(0, 8)}.jpg`;
}
