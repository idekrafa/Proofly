# Proofly AI + subscription Edge Functions

Functions in this directory keep AI usage server-authoritative:

- `revenuecat-webhook`: syncs RevenueCat events into `subscription_accounts` and period credit balances.
- `ai-credit-balance`: authenticates the caller, then returns the signed-in user's current credit balance through a service-role-only RPC.
- `ai-credit-reserve`: authenticates the caller, then reserves credits transactionally through service-role-only `proofkit_reserve_ai_credits`.
- `ai-proxy`: validates user-triggered text-only AI requests, reserves credits, calls Anthropic through the configured gateway, finalizes/refunds credits, and returns either JSON or Server-Sent Events output.
- `purchase-entitlements`: returns a compatibility entitlement snapshot for the app fallback path.
- `delete-account`: authenticates the caller, revokes their Supabase Auth sessions with the service role, deletes the Auth user, and relies on existing `on delete cascade` foreign keys for server-side account rows.

Required Supabase secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ANTHROPIC_AUTH_TOKEN`
- `REVENUECAT_WEBHOOK_AUTHORIZATION` (recommended; match RevenueCat webhook Authorization header)

Optional tuning secrets:

- `ANTHROPIC_BASE_URL` (defaults to `https://code.anyxml.com`)
- `ANTHROPIC_API_KEY` (legacy fallback if `ANTHROPIC_AUTH_TOKEN` is not set)
- `PROOFKIT_ANTHROPIC_HAIKU_MODEL` (defaults to a Haiku-class model string if unset)
- `PROOFKIT_ANTHROPIC_MESSAGES_URL` (test override; defaults to `${ANTHROPIC_BASE_URL}/v1/messages`)
- `PROOFKIT_AI_INPUT_COST_PER_MILLION_USD`
- `PROOFKIT_AI_OUTPUT_COST_PER_MILLION_USD`

Privacy rule: never log or store prompt bodies, OCR text, filenames, case titles, user notes, screenshots, or AI outputs in analytics/usage tables. The ledger stores feature, status, token counts, cost estimates, and hashes only.

Security rule: client requests must authenticate with a user JWT, but credit/entitlement table reads and AI credit mutations are performed inside Edge Functions with the service role after deriving the user id from Supabase Auth. Do not expose `SUPABASE_SERVICE_ROLE_KEY` to the iOS app or any public client.
