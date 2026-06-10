import Link from "next/link";
import { Header } from "@/components/Header";
import { createClient } from "@/lib/supabase/server";
import type { EventRow } from "@/lib/database";

export default async function Home() {
  const supabase = await createClient();
  const { data: events } = await supabase
    .from("events")
    .select("id, name, slug, status, created_at")
    .order("created_at", { ascending: false })
    .returns<Pick<EventRow, "id" | "name" | "slug" | "status" | "created_at">[]>();

  const list = events ?? [];

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-4xl px-6 py-10">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-semibold tracking-tight">Events</h1>
          <Link
            href="/events/new"
            className="rounded-md bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-zinc-800"
          >
            New event
          </Link>
        </div>

        {list.length === 0 ? (
          <div className="mt-12 rounded-xl border border-dashed border-zinc-300 bg-white p-12 text-center">
            <p className="text-zinc-500">No events yet.</p>
            <Link
              href="/events/new"
              className="mt-3 inline-block text-sm font-medium text-zinc-900 underline"
            >
              Create your first event
            </Link>
          </div>
        ) : (
          <ul className="mt-6 divide-y divide-zinc-200 overflow-hidden rounded-xl bg-white shadow-sm ring-1 ring-zinc-200">
            {list.map((event) => (
              <li key={event.id}>
                <Link
                  href={`/events/${event.slug}`}
                  className="flex items-center justify-between px-5 py-4 hover:bg-zinc-50"
                >
                  <div>
                    <p className="font-medium">{event.name}</p>
                    <p className="text-xs text-zinc-500">
                      {event.slug} · {event.status}
                    </p>
                  </div>
                  <span className="text-xs text-zinc-400">
                    {new Date(event.created_at).toLocaleDateString()}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </main>
    </>
  );
}
