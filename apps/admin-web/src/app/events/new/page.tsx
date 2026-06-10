import Link from "next/link";
import { createEvent } from "./actions";

export default async function NewEventPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <main className="mx-auto w-full max-w-xl px-6 py-12">
      <Link href="/" className="text-sm text-zinc-500 hover:text-zinc-900">
        ← Back to events
      </Link>

      <h1 className="mt-6 text-2xl font-semibold tracking-tight">New event</h1>
      <p className="mt-1 text-sm text-zinc-500">
        Templates, branding, and delivery settings can be edited after creation.
      </p>

      <form
        action={createEvent}
        className="mt-8 space-y-4 rounded-xl bg-white p-6 shadow-sm ring-1 ring-zinc-200"
      >
        {error ? (
          <div className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-200">
            {error}
          </div>
        ) : null}

        <label className="block">
          <span className="text-sm font-medium text-zinc-700">Event name</span>
          <input
            name="name"
            type="text"
            required
            placeholder="Sam & Alex's 4th of July"
            className="mt-1 block w-full rounded-md border-0 px-3 py-2 ring-1 ring-zinc-300 focus:ring-2 focus:ring-zinc-900"
          />
          <span className="mt-1 block text-xs text-zinc-500">
            A URL slug is generated automatically.
          </span>
        </label>

        <button
          type="submit"
          className="w-full rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white hover:bg-zinc-800"
        >
          Create event
        </button>
      </form>
    </main>
  );
}
