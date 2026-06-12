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

      <form
        action={createEvent}
        className="mt-8 space-y-5 rounded-2xl bg-white p-6 shadow-sm ring-1 ring-zinc-200"
      >
        {error ? (
          <div className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-200">
            {error}
          </div>
        ) : null}

        <Field label="Event name" required hint="A URL slug is generated automatically.">
          <input
            name="name"
            type="text"
            required
            placeholder="Sam & Alex's 4th of July"
            className="text-input"
          />
        </Field>

        <Field label="Description" hint="Optional — shown on admin only for now.">
          <textarea
            name="description"
            rows={2}
            placeholder="A summer afternoon in the backyard."
            className="text-input resize-none"
          />
        </Field>

        <Field label="Event date" hint="Printed at the bottom of each strip.">
          <input name="event_date" type="date" className="text-input" />
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Field label="Primary color">
            <ColorInput name="primary_color" defaultValue="#E1306C" />
          </Field>
          <Field label="Secondary color">
            <ColorInput name="secondary_color" defaultValue="#833AB4" />
          </Field>
        </div>

        <Field
          label="Shots per strip"
          hint="How many photos to capture for one strip (1–6, typically 2 or 3)."
          required
        >
          <input
            name="shots_per_strip"
            type="number"
            min={1}
            max={6}
            defaultValue={3}
            required
            className="text-input"
          />
        </Field>

        <button
          type="submit"
          className="ig-gradient w-full rounded-md px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:opacity-90"
        >
          Create event
        </button>
      </form>

      <style>{`
        .text-input {
          width: 100%;
          border-radius: 0.5rem;
          padding: 0.5rem 0.75rem;
          --tw-ring-color: rgb(212 212 216);
          box-shadow: inset 0 0 0 1px var(--tw-ring-color);
          background: white;
          outline: none;
        }
        .text-input:focus {
          --tw-ring-color: #E1306C;
          box-shadow: inset 0 0 0 2px var(--tw-ring-color);
        }
      `}</style>
    </main>
  );
}

function Field({
  label,
  hint,
  required,
  children,
}: {
  label: string;
  hint?: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="block text-sm font-medium text-zinc-700">
        {label}
        {required ? <span className="ml-1 text-ig-pink">*</span> : null}
      </span>
      <div className="mt-1">{children}</div>
      {hint ? (
        <span className="mt-1 block text-xs text-zinc-500">{hint}</span>
      ) : null}
    </label>
  );
}

function ColorInput({
  name,
  defaultValue,
}: {
  name: string;
  defaultValue: string;
}) {
  return (
    <div className="flex items-center gap-2">
      <input
        type="color"
        name={name}
        defaultValue={defaultValue}
        className="h-10 w-12 cursor-pointer rounded-md border-0 bg-transparent p-0 ring-1 ring-zinc-300"
      />
      <code className="font-mono text-sm text-zinc-600">{defaultValue}</code>
    </div>
  );
}
