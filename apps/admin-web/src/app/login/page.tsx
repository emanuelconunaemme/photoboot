import { signIn } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; next?: string }>;
}) {
  const { error, next } = await searchParams;

  return (
    <main className="flex min-h-screen items-center justify-center bg-zinc-50 p-8">
      <form
        action={signIn}
        className="w-full max-w-sm space-y-4 rounded-xl bg-white p-8 shadow-sm ring-1 ring-zinc-200"
      >
        <div>
          <h1 className="ig-gradient-text text-3xl font-bold tracking-tight">
            Photoboot
          </h1>
          <p className="mt-1 text-sm text-zinc-500">Sign in to continue</p>
        </div>

        {error ? (
          <div className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-200">
            {error}
          </div>
        ) : null}

        <input type="hidden" name="next" value={next ?? "/"} />

        <label className="block">
          <span className="text-sm font-medium text-zinc-700">Email</span>
          <input
            name="email"
            type="email"
            required
            autoComplete="email"
            className="mt-1 block w-full rounded-md border-0 px-3 py-2 ring-1 ring-zinc-300 focus:ring-2 focus:ring-zinc-900"
          />
        </label>

        <label className="block">
          <span className="text-sm font-medium text-zinc-700">Password</span>
          <input
            name="password"
            type="password"
            required
            autoComplete="current-password"
            className="mt-1 block w-full rounded-md border-0 px-3 py-2 ring-1 ring-zinc-300 focus:ring-2 focus:ring-zinc-900"
          />
        </label>

        <button
          type="submit"
          className="ig-gradient w-full rounded-md px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:opacity-90"
        >
          Sign in
        </button>
      </form>
    </main>
  );
}
