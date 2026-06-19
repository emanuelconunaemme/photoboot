"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function updateEvent(
  _prev: { error: string | null },
  formData: FormData,
): Promise<{ error: string | null }> {
  const eventId = String(formData.get("event_id") ?? "");
  if (!UUID_RE.test(eventId)) return { error: "Invalid event id" };

  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const eventDate = String(formData.get("event_date") ?? "").trim();
  const primaryColor = String(formData.get("primary_color") ?? "").trim();
  const secondaryColor = String(formData.get("secondary_color") ?? "").trim();
  const bg2x6 = formData.get("background_2x6") as File | null;
  const bg4x6 = formData.get("background_4x6") as File | null;

  if (!name) return { error: "Event name required" };
  if (!HEX_COLOR.test(primaryColor)) return { error: "Primary color must be #RRGGBB" };
  if (!HEX_COLOR.test(secondaryColor)) return { error: "Secondary color must be #RRGGBB" };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // RLS will enforce ownership; this select fails cleanly if the user doesn't own it.
  const { data: existing, error: fetchErr } = await supabase
    .from("events")
    .select("id, slug, owner_id")
    .eq("id", eventId)
    .maybeSingle();
  if (fetchErr) return { error: fetchErr.message };
  if (!existing) return { error: "Event not found" };

  type UpdatePatch = {
    name: string;
    description: string | null;
    event_date: string | null;
    primary_color: string;
    secondary_color: string;
    background_2x6_path?: string;
    background_4x6_path?: string;
  };

  const patch: UpdatePatch = {
    name,
    description: description || null,
    event_date: eventDate || null,
    primary_color: primaryColor,
    secondary_color: secondaryColor,
  };

  if (hasBytes(bg2x6)) {
    const path = await uploadBackground(supabase, eventId, "2x6", bg2x6!);
    if (typeof path === "object") return path;
    patch.background_2x6_path = path;
  }
  if (hasBytes(bg4x6)) {
    const path = await uploadBackground(supabase, eventId, "4x6", bg4x6!);
    if (typeof path === "object") return path;
    patch.background_4x6_path = path;
  }

  const { error } = await supabase.from("events").update(patch).eq("id", eventId);
  if (error) return { error: error.message };

  redirect(`/events/${existing.slug}`);
}

function hasBytes(file: File | null): boolean {
  return !!file && file.size > 0;
}

async function uploadBackground(
  supabase: Awaited<ReturnType<typeof createClient>>,
  eventId: string,
  format: "2x6" | "4x6",
  file: File,
): Promise<string | { error: string }> {
  const ext = inferExtension(file);
  const path = `${eventId}/bg-${format}.${ext}`;
  const arrayBuffer = await file.arrayBuffer();
  const { error } = await supabase.storage
    .from("templates")
    .upload(path, arrayBuffer, {
      contentType: file.type || "image/jpeg",
      upsert: true,
    });
  if (error) {
    return { error: `Couldn't upload ${format} background: ${error.message}` };
  }
  return path;
}

function inferExtension(file: File): string {
  if (file.type === "image/png") return "png";
  if (file.type === "image/webp") return "webp";
  return "jpg";
}
