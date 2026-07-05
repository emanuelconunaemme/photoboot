"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@supabase/supabase-js";
import bcrypt from "bcryptjs";
import {
  cookieName,
  signShareCookie,
  SHARE_COOKIE_MAX_AGE,
} from "@/lib/share-cookie";

const SHARE_CODE_RE = /^[A-Za-z0-9_-]{6,64}$/;

export async function verifySharePassword(
  _prev: { error: string | null },
  formData: FormData,
): Promise<{ error: string | null }> {
  const shareCode = String(formData.get("share_code") ?? "");
  const password = String(formData.get("password") ?? "");

  if (!SHARE_CODE_RE.test(shareCode)) return { error: "Invalid share link" };
  if (!password) return { error: "Password required" };

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return { error: "Server misconfigured" };

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: event } = await supabase
    .from("events")
    .select("id, share_password_hash, share_enabled")
    .eq("share_code", shareCode)
    .maybeSingle<{
      id: string;
      share_password_hash: string | null;
      share_enabled: boolean;
    }>();

  if (!event || !event.share_enabled || !event.share_password_hash) {
    return { error: "Share unavailable" };
  }

  const ok = await bcrypt.compare(password, event.share_password_hash);
  if (!ok) return { error: "Wrong password" };

  const cookieStore = await cookies();
  cookieStore.set(
    cookieName(shareCode),
    signShareCookie(shareCode, event.share_password_hash),
    {
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      path: "/",
      maxAge: SHARE_COOKIE_MAX_AGE,
    },
  );

  redirect(`/e/${shareCode}`);
}
