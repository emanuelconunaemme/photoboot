"use server";

import { redirect } from "next/navigation";
import { DEFAULT_TEMPLATE } from "@photoboot/shared";
import { createClient } from "@/lib/supabase/server";
import { slugify } from "@/lib/slug";

const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;

export type EventFormState = {
  error: string | null;
};

export const initialEventFormState: EventFormState = { error: null };

export async function createEvent(
  _prev: EventFormState,
  formData: FormData,
): Promise<EventFormState> {
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const eventDate = String(formData.get("event_date") ?? "").trim();
  const primaryColor = String(formData.get("primary_color") ?? "#E1306C").trim();
  const secondaryColor = String(formData.get("secondary_color") ?? "#833AB4").trim();
  const shotsRaw = String(formData.get("shots_per_strip") ?? "3").trim();
  const shotsPerStrip = Number.parseInt(shotsRaw, 10);

  if (!name) return { error: "Name required" };
  if (!HEX_COLOR.test(primaryColor))
    return { error: "Primary color must be #RRGGBB" };
  if (!HEX_COLOR.test(secondaryColor))
    return { error: "Secondary color must be #RRGGBB" };
  if (!Number.isFinite(shotsPerStrip) || shotsPerStrip < 1 || shotsPerStrip > 6) {
    return { error: "Shots per strip must be between 1 and 6" };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const slug = slugify(name) || `event-${Date.now()}`;
  const template = { ...DEFAULT_TEMPLATE, event: { ...DEFAULT_TEMPLATE.event, name } };

  const { data, error } = await supabase
    .from("events")
    .insert({
      owner_id: user.id,
      name,
      slug,
      template,
      description: description || null,
      event_date: eventDate || null,
      primary_color: primaryColor,
      secondary_color: secondaryColor,
      shots_per_strip: shotsPerStrip,
    })
    .select("slug")
    .single();

  if (error) return { error: error.message };

  redirect(`/events/${data.slug}`);
}
