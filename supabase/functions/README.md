# Proofly subscription Edge Functions

Functions in this directory keep entitlements server-authoritative:

- `revenuecat-webhook`: syncs RevenueCat events into `subscription_accounts`.
- `purchase-entitlements`: returns a compatibility entitlement snapshot for the app fallback path (also used by the app's service-health probe).
- `delete-account`: authenticates the caller, revokes their Supabase Auth sessions with the service role, deletes the Auth user, and relies on existing `on delete cascade` foreign keys for server-side account rows.

AI was removed from the product on 2026-07-09: the `ai-proxy`, `ai-credit-balance`, and `ai-credit-reserve` functions are gone, along with the credit tables/RPCs (migration `20260709120000_remove_ai_credit_system.sql`). Pro covers unlimited cases/proof, clean exports, and signature features only. The Anthropic secrets (`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `PROOFKIT_ANTHROPIC_*`) are no longer used and can be removed from the project.

Signature functions (`create-signature-token`, `finalize-signature-token`, `verify-signature-token`, `create-signature-request`, `sign-request`, `signature-request-status`) are documented in `docs/claude-code-pdf-signature-context.md` and `docs/ask-sign-feature.md`.

Required Supabase secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `REVENUECAT_WEBHOOK_AUTHORIZATION` (recommended; match RevenueCat webhook Authorization header)

Privacy rule: never log or store OCR text, filenames, case titles, user notes, screenshots, or file bytes in analytics tables.

Security rule: client requests must authenticate with a user JWT, but subscription table reads are performed inside Edge Functions with the service role after deriving the user id from Supabase Auth. Do not expose `SUPABASE_SERVICE_ROLE_KEY` to the iOS app or any public client.
