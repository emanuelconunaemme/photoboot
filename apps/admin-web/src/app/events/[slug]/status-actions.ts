"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { EventStatus } from "@/lib/database";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const EVENT_STATUSES: readonly EventStatus[] = ["draft", "upcoming", "live", "done"];

export async function updateEventStatus(
  eventId: string,
  status: string,
): Promise<{ error: string | null }> {
  if (!UUID_RE.test(eventId)) return { error: "Invalid event id" };
  if (!EVENT_STATUSES.includes(status as EventStatus)) {
    return { error: "Invalid status" };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in" };

  // RLS enforces ownership; the select fails cleanly if the user doesn't own it.
  const { data: event, error: fetchErr } = await supabase
    .from("events")
    .select("id, slug")
    .eq("id", eventId)
    .maybeSingle();
  if (fetchErr) return { error: fetchErr.message };
  if (!event) return { error: "Event not found" };

  const { error } = await supabase
    .from("events")
    .update({ status })
    .eq("id", eventId);
  if (error) return { error: error.message };

  revalidatePath(`/events/${event.slug}`);
  revalidatePath("/");
  return { error: null };
}
