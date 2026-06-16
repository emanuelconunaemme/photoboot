// Hand-written types mirroring the latest supabase/migrations.

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
  event_date: string | null;
  primary_color: string;
  secondary_color: string;
  shots_per_strip: number;
  invite_image_path: string | null;
  background_2x6_path: string | null;
  background_4x6_path: string | null;
  strip_title: string | null;
  strip_subtitle: string | null;
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
  composite_2x6_path: string | null;
  composite_4x6_path: string | null;
  created_at: string;
}

export interface StripPhotoRow {
  strip_id: string;
  photo_id: string;
  position: number;
}

export type StripFormat = "2x6" | "4x6";
