"use server";

import { redirect } from "next/navigation";
import { DEFAULT_TEMPLATE } from "@photoboot/shared";
import { createClient } from "@/lib/supabase/server";
import { slugify } from "@/lib/slug";

const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;

export async function createEvent(
  _prev: { error: string | null },
  formData: FormData,
): Promise<{ error: string | null }> {
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const eventDate = String(formData.get("event_date") ?? "").trim();
  const primaryColor = String(formData.get("primary_color") ?? "#E1306C").trim();
  const secondaryColor = String(formData.get("secondary_color") ?? "#833AB4").trim();
  const stripTitle = String(formData.get("strip_title") ?? "").trim();
  const stripSubtitle = String(formData.get("strip_subtitle") ?? "").trim();
  const bg2x6 = formData.get("background_2x6") as File | null;
  const bg4x6 = formData.get("background_4x6") as File | null;

  if (!name) return { error: "Event name required" };
  if (!HEX_COLOR.test(primaryColor)) return { error: "Primary color must be #RRGGBB" };
  if (!HEX_COLOR.test(secondaryColor)) return { error: "Secondary color must be #RRGGBB" };
  if (!hasBytes(bg2x6)) return { error: "2×6 background image required" };
  if (!hasBytes(bg4x6)) return { error: "4×6 background image required" };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const eventId = crypto.randomUUID();
  const slug = slugify(name) || `event-${Date.now()}`;
  const template = { ...DEFAULT_TEMPLATE, event: { ...DEFAULT_TEMPLATE.event, name } };

  const bg2x6Path = await uploadBackground(supabase, eventId, "2x6", bg2x6!);
  if (typeof bg2x6Path === "object") return bg2x6Path;
  const bg4x6Path = await uploadBackground(supabase, eventId, "4x6", bg4x6!);
  if (typeof bg4x6Path === "object") return bg4x6Path;

  const { error } = await supabase
    .from("events")
    .insert({
      id: eventId,
      owner_id: user.id,
      name,
      slug,
      template,
      description: description || null,
      event_date: eventDate || null,
      primary_color: primaryColor,
      secondary_color: secondaryColor,
      strip_title: stripTitle || null,
      strip_subtitle: stripSubtitle || null,
      background_2x6_path: bg2x6Path,
      background_4x6_path: bg4x6Path,
    });

  if (error) {
    // Best-effort cleanup of uploaded backgrounds on insert failure.
    void supabase.storage.from("templates").remove([bg2x6Path, bg4x6Path]);
    return { error: error.message };
  }

  redirect(`/events/${slug}`);
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
