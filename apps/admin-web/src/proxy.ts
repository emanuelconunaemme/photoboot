import { NextResponse, type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

const AUTH_ROUTES = ["/login"];
// Public routes — no auth required, no redirects either way:
// - /p/[id]: permanent shareable strip URL handed out via SMS/email
// - /terms, /privacy: required by Twilio toll-free SMS verification
const PUBLIC_PREFIXES = ["/p/", "/terms", "/privacy"];

export async function proxy(request: NextRequest) {
  const { response, user } = await updateSession(request);
  const path = request.nextUrl.pathname;

  const isPublic = PUBLIC_PREFIXES.some((prefix) => path.startsWith(prefix));
  if (isPublic) return response;

  const isAuthRoute = AUTH_ROUTES.some((route) => path.startsWith(route));

  if (!user && !isAuthRoute) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }

  if (user && isAuthRoute) {
    const next = request.nextUrl.searchParams.get("next") ?? "/";
    return NextResponse.redirect(new URL(next, request.url));
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
