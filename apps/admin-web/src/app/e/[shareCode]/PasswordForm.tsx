"use client";

import { useActionState } from "react";
import { verifySharePassword } from "./actions";

type State = { error: string | null };
const initial: State = { error: null };

export function PasswordForm({
  shareCode,
  eventName,
}: {
  shareCode: string;
  eventName: string;
}) {
  const [state, formAction, pending] = useActionState<State, FormData>(
    verifySharePassword,
    initial,
  );

  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-zinc-50 px-4 py-10">
      <h1 className="ig-gradient-text text-center text-3xl font-bold tracking-tight">
        {eventName}
      </h1>
      <p className="mt-2 text-sm text-zinc-500">
        Enter the password to view the gallery.
      </p>

      <form
        action={formAction}
        className="mt-8 w-full max-w-sm space-y-4 rounded-2xl bg-white p-6 shadow-sm ring-1 ring-zinc-200"
      >
        <input type="hidden" name="share_code" value={shareCode} />

        {state.error ? (
          <div
            className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-200"
            aria-live="polite"
          >
            {state.error}
          </div>
        ) : null}

        <label className="block">
          <span className="block text-sm font-medium text-zinc-700">Password</span>
          <input
            name="password"
            type="password"
            required
            autoComplete="off"
            autoFocus
            className="mt-1 w-full rounded-lg border-0 bg-white px-3 py-2 ring-1 ring-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-600"
          />
        </label>

        <button
          type="submit"
          disabled={pending}
          className="ig-gradient w-full rounded-md px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:opacity-90 disabled:opacity-60"
        >
          {pending ? "Checking…" : "View gallery"}
        </button>
      </form>

      <p className="mt-6 text-xs text-zinc-400">Made with Photoboot</p>
    </main>
  );
}
