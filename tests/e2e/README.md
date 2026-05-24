# Proofly AI, Subscription, Credits, and Cost E2E

This suite uses only synthetic cases from `tests/e2e/fixtures/synthetic-cases.json`.
Do not add real screenshots, OCR, filenames, local paths, notes, case titles, or proof files.

PostHog is intentionally out of scope. These tests use Supabase tables, RPCs, Edge Functions, local Swift source behavior, and generated test reports as the source of truth.

## What It Covers

- Subscription entitlement sync for trial, Weekly Pro, Monthly Pro, expired, and revoked states.
- Trial 3-credit, Weekly 15-credit, and Monthly 75-credit grants.
- Server-authoritative reservation, finalization, refund, concurrency, and idempotency behavior.
- `ai-proxy` integration with Anthropic mocked by default.
- Timeline Summary and Clean Up Note successful AI flows.
- Packet Polish and Deep Review credit blocking for trial users.
- Disabled server-side Ask AI features.
- Input truncation, output token caps, cost fields, usage ledger rows, and provider call counts.
- RevenueCat webhook mapping with synthetic payloads.
- Privacy leak scans of metadata/accounting tables.
- Static Swift checks for paywall copy, credit confirmation copy, local output separation, and queue guardrails.

## Default Static Check

Runs without Supabase credentials. It verifies local guardrails and writes an empty-format report:

```bash
node --test tests/e2e/proofly-ai-e2e.test.mjs
```

Reports are written to:

- `test-results/ai-usage-cost-report.json`
- `test-results/ai-usage-cost-report.md`

`test-results/` is ignored by git.

## Backend RPC E2E

Requires a Supabase project or local Supabase stack with the Proofly migrations applied.
The harness creates and deletes synthetic auth users with `@synthetic.invalid` emails.

```bash
SUPABASE_URL="http://127.0.0.1:54321" \
SUPABASE_ANON_KEY="..." \
SUPABASE_SERVICE_ROLE_KEY="..." \
node --test tests/e2e/proofly-ai-e2e.test.mjs
```

## Real Project Without Service Role In Shell

If you do not have a separate test environment and do not have `SUPABASE_SERVICE_ROLE_KEY` in the shell, use the rollback-safe SQL smoke through Supabase MCP or the Supabase SQL editor:

```sql
-- Run the contents of:
-- tests/e2e/proofly-backend-rpc-smoke.sql
```

This smoke inserts fixed synthetic auth users, exercises the real subscription/credit/ledger RPCs, asserts pricing and privacy invariants, then deletes the fixed users so cascades remove synthetic subscription, balance, and ledger rows. The final result includes `leftover_subscription_rows` and `leftover_ledger_rows`, which should both be `0`.

## Full Mocked Edge E2E

Mocked AI is the default for automated Edge tests. This path starts a local Anthropic mock and `supabase functions serve`, then points `ai-proxy` at the mock via `PROOFKIT_ANTHROPIC_MESSAGES_URL`.

```bash
SUPABASE_URL="http://127.0.0.1:54321" \
SUPABASE_ANON_KEY="..." \
SUPABASE_SERVICE_ROLE_KEY="..." \
PROOFKIT_E2E_SPAWN_FUNCTIONS=true \
node --test tests/e2e/proofly-ai-e2e.test.mjs
```

For a remote/staging database with locally served functions, keep `SUPABASE_URL` pointed at that project and still use `PROOFKIT_E2E_SPAWN_FUNCTIONS=true`.

## Tiny Live AI E2E

Live AI is opt-in and must use synthetic fixtures only. It runs at most one Timeline Summary and one Clean Up Note through the configured Edge Function. Do not enable live Deep Review automation.

```bash
SUPABASE_URL="https://PROJECT_REF.supabase.co" \
SUPABASE_ANON_KEY="..." \
SUPABASE_SERVICE_ROLE_KEY="..." \
LIVE_AI_E2E=true \
node --test tests/e2e/proofly-ai-e2e.test.mjs
```

Use a staging project or a deliberately isolated test user pool. The live provider spend is reported in `test-results/ai-usage-cost-report.*` when the Edge Function has token and cost data available.

## Existing Mock Edge Target

If the Edge Function is already served elsewhere and is already configured to use a mock Anthropic endpoint, run:

```bash
SUPABASE_URL="https://PROJECT_REF.supabase.co" \
SUPABASE_ANON_KEY="..." \
SUPABASE_SERVICE_ROLE_KEY="..." \
PROOFKIT_E2E_FUNCTIONS_URL="http://127.0.0.1:54321/functions/v1" \
PROOFKIT_E2E_CONFIRM_MOCK_EDGE=true \
node --test tests/e2e/proofly-ai-e2e.test.mjs
```

Only use `PROOFKIT_E2E_CONFIRM_MOCK_EDGE=true` when you have verified that the target Edge Function cannot call real Anthropic.

## Optional Analytics Table Scan

The core suite does not fetch from PostHog. If a privacy-safe internal analytics table exists in Supabase, add it to the remote leak scan:

```bash
PROOFKIT_E2E_ANALYTICS_TABLES="analytics_events,app_events"
```

The scan asserts the configured tables do not contain synthetic OCR bodies, prompt text, AI output text, filenames, paths, case titles, user notes, or file-byte markers.

## Manual App Store Sandbox Checklist

Automated E2E does not require live App Store purchases. For real sandbox purchase validation, use `tests/e2e/manual-sandbox-purchase-checklist.md`.
