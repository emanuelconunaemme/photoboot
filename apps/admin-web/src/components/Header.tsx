import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export async function Header() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  return (
    <header className="flex items-center justify-between border-b border-zinc-200 bg-white px-6 py-3">
      <Link href="/" className="text-sm font-semibold tracking-tight">
        Photoboot
      </Link>
      <div className="flex items-center gap-3">
        <span className="text-sm text-zinc-500">{user.email}</span>
        <form action="/auth/signout" method="post">
          <button
            type="submit"
            className="rounded-md px-3 py-1.5 text-sm text-zinc-600 hover:bg-zinc-100"
          >
            Sign out
          </button>
        </form>
      </div>
    </header>
  );
}
