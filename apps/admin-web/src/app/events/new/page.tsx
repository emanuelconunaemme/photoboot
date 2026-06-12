import Link from "next/link";
import { NewEventForm } from "./NewEventForm";

export default function NewEventPage() {
  return (
    <main className="mx-auto w-full max-w-xl px-6 py-12">
      <Link
        href="/"
        className="text-ig-pink hover:text-ig-purple text-sm font-medium transition"
      >
        ← Back to events
      </Link>

      <h1 className="ig-gradient-text mt-6 text-3xl font-bold tracking-tight">
        New event
      </h1>
      <p className="mt-1 text-sm text-zinc-500">
        These settings drive how the iPad app captures and brands the photo
        strips.
      </p>

      <NewEventForm />
    </main>
  );
}
