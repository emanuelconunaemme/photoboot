SHELL := /bin/bash

# ────────────────────────────────────────────────────────────────────
# Photoboot — convenience commands. `make` with no args prints this.
# ────────────────────────────────────────────────────────────────────

PROJECT_REF := fyhddmerdksdbdryvtaf
SUPABASE    := pnpm supabase

.PHONY: help
help:  ## Show this help
	@grep -hE '^[a-zA-Z_.-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ──────────────────── monorepo ────────────────────

.PHONY: install
install:  ## Install all pnpm dependencies
	pnpm install

.PHONY: clean
clean:  ## Remove build + cache artifacts
	rm -rf apps/admin-web/.next apps/admin-web/.turbo .turbo

# ──────────────────── supabase (cloud) ────────────────────

.PHONY: login
login:  ## Authenticate with Supabase (opens browser)
	$(SUPABASE) login

.PHONY: link
link:  ## Link this repo to the cloud project ($(PROJECT_REF))
	$(SUPABASE) link --project-ref $(PROJECT_REF)

.PHONY: push
push:  ## Push migrations to cloud (run after each new migration)
	$(SUPABASE) db push

# NOTE: we deliberately do NOT auto-push config.toml. The CLI's config sync
# can silently disable auth providers (we lost email login once that way).
# Manage auth/storage/realtime settings in the Supabase dashboard. config.toml
# is kept as documentation + local-stack config only.

.PHONY: pull
pull:  ## Pull the cloud schema into a new local migration
	$(SUPABASE) db pull

.PHONY: diff
diff:  ## Show schema drift between local and cloud
	$(SUPABASE) db diff --linked

.PHONY: migration
migration:  ## Create a new migration: make migration name=add_thing
	@[ "$(name)" ] || (echo "Usage: make migration name=add_something" && exit 1)
	$(SUPABASE) migration new $(name)

# ──────────────────── supabase (local dev) ────────────────────

.PHONY: start
start:  ## Boot local Supabase (Docker)
	$(SUPABASE) start

.PHONY: stop
stop:  ## Stop local Supabase
	$(SUPABASE) stop

.PHONY: status
status:  ## Print local Supabase URLs + keys
	$(SUPABASE) status

.PHONY: reset
reset:  ## Drop local DB + re-apply all migrations + seed
	$(SUPABASE) db reset

.PHONY: types
types:  ## Regenerate TS types into packages/shared
	$(SUPABASE) gen types typescript --local > packages/shared/src/database.types.ts

# ──────────────────── admin-web ────────────────────

.PHONY: dev
dev:  ## Run admin-web dev server (http://localhost:3000)
	pnpm --filter admin-web dev

.PHONY: build
build:  ## Build admin-web for production
	pnpm --filter admin-web build

.PHONY: lint
lint:  ## Lint admin-web
	pnpm --filter admin-web lint

.PHONY: typecheck
typecheck:  ## Typecheck admin-web + shared
	pnpm --filter admin-web typecheck
	pnpm --filter @photoboot/shared typecheck

# ──────────────────── iPad ────────────────────

.PHONY: ipad
ipad:  ## Regenerate Xcode project from project.yml
	cd apps/client-ipad && xcodegen generate

.PHONY: ipad-open
ipad-open: ipad  ## Regenerate Xcode project and open it
	open apps/client-ipad/Photoboot.xcodeproj
