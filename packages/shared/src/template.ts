// TS mirror of template.schema.json. Keep in sync — the JSON Schema is the
// source of truth (validated at the edge), this is for compile-time ergonomics.
// Codegen from the JSON Schema is a TODO once the shape settles.

export type CaptureModeId = "single" | "strip-4";
export type CaptureLayout = "single" | "vertical-strip" | "grid-2x2";

export interface CaptureMode {
  id: CaptureModeId;
  label: string;
  shots: number;
  countdown_seconds: number;
  layout?: CaptureLayout;
}

export interface PhotobootTemplate {
  version: 1;
  event: {
    name: string;
    logo_url?: string;
    theme_color: string;
    accent_color?: string;
  };
  home_screen: {
    title: string;
    subtitle?: string;
    cta_label?: string;
    background_url?: string;
  };
  capture_modes: CaptureMode[];
  overlay?: {
    frame_url?: string;
    text?: string;
    text_position?: "top" | "bottom";
  };
  delivery: {
    sms_enabled: boolean;
    email_enabled: boolean;
    print_enabled: boolean;
    sms_message?: string;
    email_subject?: string;
    email_body?: string;
  };
}

export const DEFAULT_TEMPLATE: PhotobootTemplate = {
  version: 1,
  event: {
    name: "New Event",
    theme_color: "#1f2937",
  },
  home_screen: {
    title: "Welcome!",
    cta_label: "Tap to start",
  },
  capture_modes: [
    { id: "single", label: "Single", shots: 1, countdown_seconds: 3, layout: "single" },
  ],
  delivery: {
    sms_enabled: true,
    email_enabled: true,
    print_enabled: false,
  },
};
