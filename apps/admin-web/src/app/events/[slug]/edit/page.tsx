import Link from "next/link";
import { notFound } from "next/navigation";
import { Header } from "@/components/Header";
import { createClient } from "@/lib/supabase/server";
import type { EventRow } from "@/lib/database";
import { EditEventForm, type EditInitialValues } from "./EditEventForm";

export default async function EditEventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const supabase = await createClient();

  const { data: event } = await supabase
    .from("events")
    .select(
      "id, name, slug, description, event_date, primary_color, secondary_color, strip_title, strip_subtitle, background_2x6_path, background_4x6_path, updated_at",
    )
    .eq("slug", slug)
    .maybeSingle<
      Pick<
        EventRow,
        | "id"
        | "name"
        | "slug"
        | "description"
        | "event_date"
        | "primary_color"
        | "secondary_color"
        | "strip_title"
        | "strip_subtitle"
        | "background_2x6_path"
        | "background_4x6_path"
        | "updated_at"
      >
    >();

  if (!event) notFound();

  const version = encodeURIComponent(event.updated_at);
  const bg2x6Url = event.background_2x6_path
    ? `${supabase.storage.from("templates").getPublicUrl(event.background_2x6_path).data.publicUrl}?v=${version}`
    : null;
  const bg4x6Url = event.background_4x6_path
    ? `${supabase.storage.from("templates").getPublicUrl(event.background_4x6_path).data.publicUrl}?v=${version}`
    : null;

  const initial: EditInitialValues = {
    eventId: event.id,
    name: event.name,
    description: event.description ?? "",
    eventDate: event.event_date ?? "",
    primaryColor: event.primary_color,
    secondaryColor: event.secondary_color,
    stripTitle: event.strip_title ?? "",
    stripSubtitle: event.strip_subtitle ?? "",
    bg2x6Url,
    bg4x6Url,
  };

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-xl px-6 py-12">
        <Link
          href={`/events/${event.slug}`}
          className="text-ig-pink hover:text-ig-purple text-sm font-medium transition"
        >
          ← Back to event
        </Link>

        <h1 className="ig-gradient-text mt-6 text-3xl font-bold tracking-tight">
          Edit event
        </h1>
        <p className="mt-1 text-sm text-zinc-500">
          The URL slug stays the same. Leave file pickers blank to keep current backgrounds.
        </p>

        <EditEventForm initial={initial} />
      </main>
    </>
  );
}
