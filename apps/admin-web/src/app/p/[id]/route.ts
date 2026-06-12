import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

// Permanent shareable URL for a strip. Server-side it issues a fresh
// short-lived signed URL for the composite and 302-redirects to it.
// The strip_id is a UUID (128 bits) so the link itself functions as the
// unguessable secret; revoking access = deleting the strip.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SIGNED_URL_TTL_SECONDS = 3600;

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;

  if (!UUID_RE.test(id)) {
    return new NextResponse("Not found", { status: 404 });
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    return new NextResponse("Server misconfigured", { status: 500 });
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: strip } = await supabase
    .from("strips")
    .select("composite_path")
    .eq("id", id)
    .maybeSingle();

  if (!strip?.composite_path) {
    return new NextResponse("Not found", { status: 404 });
  }

  const { data: signed, error } = await supabase.storage
    .from("composites")
    .createSignedUrl(strip.composite_path, SIGNED_URL_TTL_SECONDS);

  if (error || !signed?.signedUrl) {
    return new NextResponse("Couldn't generate URL", { status: 500 });
  }

  return NextResponse.redirect(signed.signedUrl, 302);
}
