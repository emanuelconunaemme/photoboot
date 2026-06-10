"use server";

import { redirect } from "next/navigation";
import { DEFAULT_TEMPLATE } from "@photoboot/shared";
import { createClient } from "@/lib/supabase/server";
import { slugify } from "@/lib/slug";

export async function createEvent(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) {
    redirect("/events/new?error=Name+required");
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
    })
    .select("slug")
    .single();

  if (error) {
    redirect(`/events/new?error=${encodeURIComponent(error.message)}`);
  }
  redirect(`/events/${data.slug}`);
}
