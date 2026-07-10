import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";
import {
  cookieName,
  signShareCookie,
  SHARE_COOKIE_MAX_AGE,
} from "@/lib/share-cookie";

const SHARE_CODE_RE = /^[A-Za-z0-9_-]{6,64}$/;
const TOKEN_RE = /^[A-Za-z0-9_-]{16,128}$/;

export async function GET(
  req: NextRequest,
  ctx: { params: Promise<{ shareCode: string; token: string }> },
) {
  const { shareCode, token } = await ctx.params;

  if (!SHARE_CODE_RE.test(shareCode) || !TOKEN_RE.test(token)) {
    return new NextResponse("Not found", { status: 404 });
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey || !process.env.SHARE_COOKIE_SECRET) {
    return new NextResponse("Server misconfigured", { status: 500 });
  }

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
    return new NextResponse("Not found", { status: 404 });
  }

  const { data: recipient } = await supabase
    .from("event_share_recipients")
    .select("id")
    .eq("event_id", event.id)
    .eq("token", token)
    .maybeSingle();

  const dest = new URL(`/e/${shareCode}`, req.url);
  if (!recipient) {
    // Bad or revoked token — send to password prompt instead of a 404 so the
    // recipient can still enter the password manually if they have it.
    return NextResponse.redirect(dest);
  }

  const response = NextResponse.redirect(dest);
  response.cookies.set(
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
  return response;
}
