"use client";

import { useActionState } from "react";
import { createEvent } from "./actions";

type EventFormState = { error: string | null };
const initialState: EventFormState = { error: null };

export function NewEventForm() {
  const [state, formAction, pending] = useActionState<EventFormState, FormData>(
    createEvent,
    initialState,
  );

  return (
    <form
      action={formAction}
      className="mt-8 space-y-5 rounded-2xl bg-white p-6 shadow-sm ring-1 ring-zinc-200"
    >
      {state.error ? (
        <div className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-200">
          {state.error}
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

      <Field label="Event date" hint="Used as the default subtitle if you leave it blank below.">
        <input name="event_date" type="date" className="text-input" />
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Primary color" hint="Strip title color">
          <ColorInput name="primary_color" defaultValue="#E1306C" />
        </Field>
        <Field label="Secondary color" hint="Strip subtitle color">
          <ColorInput name="secondary_color" defaultValue="#833AB4" />
        </Field>
      </div>

      <Field label="Strip title" hint="Shown on every strip. Often the event name in shorter form.">
        <input
          name="strip_title"
          type="text"
          placeholder="Sam & Alex"
          className="text-input"
        />
      </Field>

      <Field label="Strip subtitle" hint="A date, a tagline, anything. Leave blank to skip.">
        <input
          name="strip_subtitle"
          type="text"
          placeholder="July 4, 2026"
          className="text-input"
        />
      </Field>

      <hr className="border-zinc-200" />

      <div>
        <h2 className="text-sm font-semibold text-zinc-700">Backgrounds</h2>
        <p className="mt-1 text-xs text-zinc-500">
          Two images, one per print format. Photos overlay these. Both
          required.
        </p>
      </div>

      <Field
        label="2×6 strip background"
        required
        hint="Portrait, fills the strip. Aim ~600×1800 (or higher)."
      >
        <input
          name="background_2x6"
          type="file"
          accept="image/jpeg,image/png,image/webp"
          required
          className="file-input"
        />
      </Field>

      <Field
        label="4×6 print background"
        required
        hint="Landscape, fills the print. Photos sit on the left half. Aim ~1800×1200."
      >
        <input
          name="background_4x6"
          type="file"
          accept="image/jpeg,image/png,image/webp"
          required
          className="file-input"
        />
      </Field>

      <button
        type="submit"
        disabled={pending}
        className="ig-gradient w-full rounded-md px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:opacity-90 disabled:opacity-60"
      >
        {pending ? "Creating…" : "Create event"}
      </button>

      <style>{`
        .text-input {
          width: 100%;
          border: none;
          border-radius: 0.5rem;
          padding: 0.5rem 0.75rem;
          box-shadow: inset 0 0 0 1px #34D399;
          background: white;
          outline: none;
        }
        .text-input:focus {
          box-shadow: inset 0 0 0 2px #059669;
        }
        .file-input {
          width: 100%;
          padding: 0.5rem 0;
          font-size: 0.875rem;
        }
        .file-input::file-selector-button {
          padding: 0.4rem 0.75rem;
          margin-right: 0.75rem;
          border-radius: 0.375rem;
          border: 1px solid #d4d4d8;
          background: #fafafa;
          cursor: pointer;
          font-weight: 500;
        }
        .file-input::file-selector-button:hover {
          background: #f4f4f5;
        }
      `}</style>
    </form>
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
        className="h-10 w-12 cursor-pointer rounded-md border-0 bg-transparent p-0 ring-1 ring-emerald-400"
      />
      <code className="font-mono text-sm text-zinc-600">{defaultValue}</code>
    </div>
  );
}
