import Link from "next/link";
import { Header } from "@/components/Header";
import { createClient } from "@/lib/supabase/server";
import type { EventRow } from "@/lib/database";

const STATUS_CLASSES: Record<string, string> = {
  draft: "bg-zinc-100 text-zinc-600 ring-zinc-200",
  live: "ig-gradient text-white ring-transparent",
  archived: "bg-zinc-200 text-zinc-500 ring-zinc-300",
};

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
          <h1 className="ig-gradient-text text-3xl font-bold tracking-tight">
            Events
          </h1>
          <Link
            href="/events/new"
            className="ig-gradient inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:opacity-90"
          >
            <span className="text-base leading-none">+</span> New event
          </Link>
        </div>

        {list.length === 0 ? (
          <div className="mt-12 flex flex-col items-center gap-3 rounded-3xl border border-dashed border-zinc-300 bg-white p-16 text-center">
            <div className="ig-gradient flex h-16 w-16 items-center justify-center rounded-full text-3xl text-white shadow-md">
              ✨
            </div>
            <p className="ig-gradient-text text-xl font-bold">No events yet</p>
            <p className="text-sm text-zinc-500">
              Create your first one to start capturing photos.
            </p>
            <Link
              href="/events/new"
              className="ig-gradient mt-2 rounded-full px-5 py-2 text-sm font-semibold text-white shadow-sm hover:opacity-90"
            >
              Create event
            </Link>
          </div>
        ) : (
          <ul className="mt-6 grid gap-4 sm:grid-cols-2">
            {list.map((event) => {
              const statusClass =
                STATUS_CLASSES[event.status] ?? STATUS_CLASSES.draft;
              return (
                <li key={event.id}>
                  <Link
                    href={`/events/${event.slug}`}
                    className="ig-gradient block rounded-2xl p-[2px] shadow-sm transition hover:shadow-md"
                  >
                    <div className="rounded-[14px] bg-white px-5 py-4">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="truncate text-lg font-semibold tracking-tight">
                            {event.name}
                          </p>
                          <p className="mt-1 truncate font-mono text-xs text-zinc-500">
                            {event.slug}
                          </p>
                        </div>
                        <span
                          className={`inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ${statusClass}`}
                        >
                          {event.status}
                        </span>
                      </div>
                      <p className="mt-3 text-xs text-zinc-400">
                        Created{" "}
                        {new Date(event.created_at).toLocaleDateString(
                          undefined,
                          {
                            month: "short",
                            day: "numeric",
                            year: "numeric",
                          },
                        )}
                      </p>
                    </div>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </main>
    </>
  );
}
