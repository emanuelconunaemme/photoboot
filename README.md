# photoboot

Custom iPad photo booth app for reusable event photo capture, delivery, and printing. This is a monorepo that includes the client and backend code.

## Layout

```
apps/
  admin-web/      Next.js SPA (Vercel) — event management, templates, gallery
  client-ipad/    SwiftUI app — kiosk capture, AirPrint, gallery
packages/
  shared/         JSON Schema + TS types for templates (Swift codegen later)
supabase/
  migrations/     Versioned SQL
  functions/      Edge Functions (delivery, gphotos sync, recap sheet)
```

The iPad app lives in the monorepo for shared history but is not part of the pnpm workspace (Xcode owns its build).

## Prerequisites

- Node 20+, pnpm 10+
- Docker (for Supabase local stack)
- Xcode 16+ (full IDE, not just Command Line Tools)
- `supabase` CLI, `xcodegen` (`brew install supabase/tap/supabase xcodegen`)

## First-time setup

```sh
pnpm install
cp .env.example .env.local
supabase start                 # boots local Postgres + storage on Docker
pnpm --filter admin-web dev    # admin at http://localhost:3000
cd apps/client-ipad && xcodegen generate && open Photoboot.xcodeproj
```

## Build order

See `MEMORY.md` (private to Claude) — phases 0–6 mapped to weekends through July 4, 2026.
