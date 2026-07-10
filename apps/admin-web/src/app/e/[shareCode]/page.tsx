import { notFound } from "next/navigation";
import Link from "next/link";
import { cookies } from "next/headers";
import { createClient } from "@supabase/supabase-js";
import { PasswordForm } from "./PasswordForm";
import { cookieName, verifyShareCookie } from "@/lib/share-cookie";

const SHARE_CODE_RE = /^[A-Za-z0-9_-]{6,64}$/;
const SIGNED_URL_TTL_SECONDS = 3600;

interface EventRow {
  id: string;
  name: string;
  event_date: string | null;
  share_code: string;
  share_password_hash: string | null;
  share_enabled: boolean;
}

interface StripRow {
  id: string;
  composite_2x6_path: string | null;
  composite_4x6_path: string | null;
  created_at: string;
}

export default async function ShareEventPage({
  params,
}: {
  params: Promise<{ shareCode: string }>;
}) {
  const { shareCode } = await params;
  if (!SHARE_CODE_RE.test(shareCode)) notFound();

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

  const { data: event } = await supabase
    .from("events")
    .select("id, name, event_date, share_code, share_password_hash, share_enabled")
    .eq("share_code", shareCode)
    .maybeSingle<EventRow>();

  if (!event || !event.share_enabled || !event.share_password_hash) {
    notFound();
  }

  const cookieStore = await cookies();
  const cookieValue = cookieStore.get(cookieName(shareCode))?.value ?? "";
  const authorized = verifyShareCookie(
    shareCode,
    event.share_password_hash,
    cookieValue,
  );

  if (!authorized) {
    return <PasswordForm shareCode={shareCode} eventName={event.name} />;
  }

  const [{ data: strips }, photoCount, stripCount, deliveryRows] = await Promise.all([
    supabase
      .from("strips")
      .select("id, composite_2x6_path, composite_4x6_path, created_at")
      .eq("event_id", event.id)
      .order("created_at", { ascending: false })
      .returns<StripRow[]>(),
    supabase
      .from("photos")
      .select("id", { count: "exact", head: true })
      .eq("event_id", event.id),
    supabase
      .from("strips")
      .select("id", { count: "exact", head: true })
      .eq("event_id", event.id),
    // Only counts for sent deliveries — guests don't need to see
    // pending/failed. Join through strips because deliveries don't
    // carry event_id directly.
    supabase
      .from("deliveries")
      .select("channel, strips!inner(event_id)")
      .eq("strips.event_id", event.id)
      .eq("status", "sent"),
  ]);

  const readyStrips = (strips ?? []).filter(
    (s) => s.composite_2x6_path || s.composite_4x6_path,
  );

  const thumbPaths = readyStrips
    .map((s) => s.composite_2x6_path ?? s.composite_4x6_path)
    .filter((p): p is string => p !== null);

  const signed = thumbPaths.length
    ? await supabase.storage
        .from("composites")
        .createSignedUrls(thumbPaths, SIGNED_URL_TTL_SECONDS)
    : { data: [] };
  const urlByPath = new Map(
    (signed.data ?? []).map((entry) => [entry.path ?? "", entry.signedUrl]),
  );

  const photosTaken = photoCount.count ?? 0;
  const stripsCreated = stripCount.count ?? 0;
  const sentRows = deliveryRows.data ?? [];
  const smsSent = sentRows.filter((r) => r.channel === "sms").length;
  const emailSent = sentRows.filter((r) => r.channel === "email").length;
  const printCount = sentRows.filter((r) => r.channel === "print").length;
  const airdropCount = sentRows.filter((r) => r.channel === "airdrop").length;

  const eventDate = event.event_date
    ? new Date(event.event_date + "T00:00:00Z").toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
        timeZone: "UTC",
      })
    : null;

  return (
    <main className="flex min-h-screen flex-col items-center bg-zinc-50 px-4 py-10">
      <Link
        href="/"
        className="ig-gradient-text mb-8 text-lg font-bold tracking-tight"
      >
        Photoboot ✨
      </Link>

      <h1 className="ig-gradient-text text-center text-3xl font-bold tracking-tight">
        {event.name}
      </h1>
      {eventDate ? (
        <p className="mt-1 text-sm text-zinc-500">{eventDate}</p>
      ) : null}
      <p className="mt-2 text-sm text-zinc-500">
        Tap any strip to view and download.
      </p>

      <section className="mt-8 grid w-full max-w-5xl grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <NumberStat label="Photos taken" value={photosTaken} />
        <NumberStat label="Strips created" value={stripsCreated} />
        <NumberStat label="Prints" value={printCount} />
        <NumberStat label="AirDrops" value={airdropCount} />
        <NumberStat label="SMS sent" value={smsSent} />
        <NumberStat label="Email sent" value={emailSent} />
      </section>

      {readyStrips.length === 0 ? (
        <p className="mt-16 text-sm text-zinc-500">
          No strips yet. Check back soon.
        </p>
      ) : (
        <div className="mt-8 grid w-full max-w-5xl grid-cols-2 gap-5 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
          {readyStrips.map((strip) => {
            const thumbPath =
              strip.composite_2x6_path ?? strip.composite_4x6_path;
            const thumb = thumbPath ? urlByPath.get(thumbPath) ?? null : null;
            if (!thumb) return null;
            const isPortrait = Boolean(strip.composite_2x6_path);
            const aspect = isPortrait ? "aspect-[1/3]" : "aspect-[3/2]";
            return (
              <Link
                key={strip.id}
                href={`/p/${strip.id}`}
                className="group block"
              >
                <div className="ig-gradient rounded-2xl p-[3px] shadow-sm transition group-hover:opacity-90">
                  <div
                    className={`${aspect} overflow-hidden rounded-[14px] bg-white`}
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={thumb}
                      alt={`Strip ${strip.id.slice(0, 8)}`}
                      className="h-full w-full object-contain"
                    />
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}

      <p className="mt-16 text-xs text-zinc-400">Made with Photoboot</p>
    </main>
  );
}

function NumberStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-zinc-200">
      <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
        {label}
      </p>
      <p className="ig-gradient-text mt-2 text-3xl font-bold tracking-tight">
        {value}
      </p>
    </div>
  );
}
