// Hand-written types mirroring the latest supabase/migrations.
// Replace with codegen output (`pnpm supabase gen types typescript --local`)
// once the local stack is reliably running. Re-export from @photoboot/shared.

import type { PhotobootTemplate } from "@photoboot/shared";

export type EventStatus = "draft" | "live" | "archived";

export interface EventRow {
  id: string;
  owner_id: string;
  name: string;
  slug: string;
  status: EventStatus;
  template: PhotobootTemplate;
  description: string | null;
  event_date: string | null;          // "YYYY-MM-DD" from Postgres date
  primary_color: string;              // "#RRGGBB"
  secondary_color: string;            // "#RRGGBB"
  shots_per_strip: number;            // 1..6
  invite_image_path: string | null;
  gphotos_album_id: string | null;
  gphotos_share_url: string | null;
  created_at: string;
  updated_at: string;
}

export type PhotoStatus = "uploading" | "ready" | "failed";
export type CaptureMode = "single" | "strip" | "strip-4";

export interface PhotoRow {
  id: string;
  event_id: string;
  status: PhotoStatus;
  capture_mode: CaptureMode;
  storage_path: string | null;
  composite_path: string | null;
  gphotos_media_id: string | null;
  width: number | null;
  height: number | null;
  error: string | null;
  taken_at: string;
  ready_at: string | null;
}

export interface StripRow {
  id: string;
  event_id: string;
  composite_path: string | null;
  created_at: string;
}

export interface StripPhotoRow {
  strip_id: string;
  photo_id: string;
  position: number;
}
