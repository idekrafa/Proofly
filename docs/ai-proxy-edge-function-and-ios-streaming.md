# ProofKit AI Proxy Edge Function and iOS Streaming Notes

> **Note (2026-07-09):** AI was removed from Proofly entirely — the `ai-proxy`,
> `ai-credit-balance`, and `ai-credit-reserve` Edge Functions, the credit
> tables/RPCs (migration `20260709120000_remove_ai_credit_system.sql`), and all
> in-app AI features (Timeline Summary, Packet Polish, Clean Up Note). The Pro
> plan no longer includes AI services. This document is historical.

Date: 2026-05-21

## Summary

This work added a secure Supabase Edge Function path for ProofKit AI actions and updated the iOS app to call it with the signed-in user's Supabase session instead of any AI provider key.

The intended request flow is:

1. iOS builds a sanitized, compressed text-only prompt payload from local SwiftData case/evidence data.
2. iOS calls `supabase/functions/ai-proxy` with the user's Supabase access token in `Authorization`.
3. The Edge Function authenticates the user, normalizes the requested feature, and reserves credits with `proofkit_reserve_ai_credits`.
4. If credits are insufficient, the function returns `402 Payment Required`.
5. If reservation succeeds, the function calls Claude through the configured gateway.
6. Streaming requests return Server-Sent Events (`start`, `delta`, `done`, `error`) so the UI can update in real time.
7. Successful provider responses finalize the ledger through `proofkit_finalize_ai_usage`.
8. Provider/config/function failures refund the reservation through `proofkit_refund_ai_reservation`.

## Current Deployment Status

The linked Supabase project is:

`zvwixgdclmrhopsbuqld`

Remote function inspection through the Supabase connector shows:

- `ai-proxy` exists.
- Status is `ACTIVE`.
- `verify_jwt` is `true`.
- Remote version is `3`.

However, the deployed `ai-proxy` is not the latest implementation from this workspace. The remote function contents are older and still:

- call `https://api.anthropic.com/v1/messages`
- read `ANTHROPIC_API_KEY`
- do not support SSE streaming
- do not return `402` for insufficient-credit reservation failures
- do not use the new `ANTHROPIC_AUTH_TOKEN` / `https://code.anyxml.com` gateway defaults

Conclusion: the Edge Function is active, but it is not properly deployed for the new Claude gateway + streaming + credit-security requirements yet.

## Deployment Command

Use this after confirming the production Supabase secrets are set:

```bash
supabase functions deploy ai-proxy --project-ref zvwixgdclmrhopsbuqld --use-api
```

Do not pass `--no-verify-jwt`; this function should require a valid user JWT.

This local shell could not list/deploy functions through the Supabase CLI because no CLI access token is configured:

```text
Access token not provided. Supply an access token by running supabase login or setting the SUPABASE_ACCESS_TOKEN environment variable.
```

The Supabase connector was still able to inspect the remote deployed function.

## Required Supabase Secrets

Required:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ANTHROPIC_AUTH_TOKEN`

Recommended/optional:

- `ANTHROPIC_BASE_URL`, defaulting to `https://code.anyxml.com`
- `PROOFKIT_ANTHROPIC_HAIKU_MODEL`, defaulting to `claude-haiku-4-5-20251001`
- `PROOFKIT_AI_INPUT_COST_PER_MILLION_USD`
- `PROOFKIT_AI_OUTPUT_COST_PER_MILLION_USD`
- `PROOFKIT_ANTHROPIC_MESSAGES_URL` for test overrides only

`ANTHROPIC_API_KEY` remains a legacy fallback in the local implementation, but `ANTHROPIC_AUTH_TOKEN` is the intended secret name for the gateway path.

## Edge Function Changes

File:

`supabase/functions/ai-proxy/index.ts`

Implemented locally:

- Authenticates the caller through `requireUser(req)`.
- Accepts `case_id` and the existing iOS `caseID` field.
- Normalizes `feature` / `taskType`.
- Enforces text-only payload presence.
- Loads enabled pricing from `ai_feature_pricing`.
- Guards duplicate idempotency keys before provider calls.
- Calls `proofkit_reserve_ai_credits` with the verified user id.
- Maps insufficient-credit reservation failures to `402 Payment Required`.
- Reads `ANTHROPIC_AUTH_TOKEN`, with `ANTHROPIC_API_KEY` as a fallback.
- Defaults provider URL to `https://code.anyxml.com/v1/messages`.
- Supports non-streaming JSON responses for compatibility.
- Supports SSE streaming when `stream == true` or `Accept: text/event-stream`.
- Sends SSE events:
  - `start`: ledger/model/credit metadata
  - `delta`: incremental text
  - `done`: final app-compatible `AIProxyTextResponse`
  - `error`: stream failure
- Finalizes successful usage with `proofkit_finalize_ai_usage`.
- Refunds provider/config/empty-output/function failures with `proofkit_refund_ai_reservation`.

## iOS Changes

Files:

- `ProofKit/Supabase/SupabaseInfrastructureModels.swift`
- `ProofKit/Supabase/SupabaseInfrastructureProtocols.swift`
- `ProofKit/Supabase/SupabaseInfrastructureService.swift`
- `ProofKit/AI/AITaskRouter.swift`
- `ProofKit/AI/AIService.swift`

Implemented locally:

- Added optional `stream` to `AIProxyTextRequest`.
- Added `AIProxyStreamEvent`, `AIProxyStreamStart`, and stream delta/error decoding.
- Added `AIProxyServicing.streamTextOnlyAI(_:)`.
- Implemented SSE parsing over `URLSession.shared.bytes(for:)`.
- Sends:
  - `Content-Type: application/json`
  - `Accept: text/event-stream`
  - `apikey: <Supabase publishable key>`
  - `Authorization: Bearer <current Supabase session access token>`
- Does not store or send Claude provider secrets from Swift.
- Added `AITaskRouter.routeStreaming(...)`.
- Added `AIService.runAIAction(feature:caseId:for:in:onDelta:)`.
- Completed streamed responses are stored through the existing `AIResultCache` path.

## Privacy and Data Preservation

The app remains local-first for user evidence. The Edge Function accepts sanitized text payloads because the server does not own the user's local SwiftData case/evidence records.

This change does not touch:

- SwiftData models
- SwiftData properties or relationships
- delete rules
- identifiers
- model-container configuration
- storage paths
- local migrations
- sign-in/sign-out local storage behavior
- account switching local storage behavior

The implementation does not upload:

- raw images
- PDFs
- attachment bytes
- local file paths
- thumbnail references

AI output remains separate from original evidence and is stored only after completion through the existing cache/result path. Original OCR, user notes, documents, photos, settings, progress, and account-scoped local data remain the source of truth.

## Verification Performed

Passed:

```bash
git diff --check -- supabase/functions/ai-proxy/index.ts ProofKit/Supabase/SupabaseInfrastructureModels.swift ProofKit/Supabase/SupabaseInfrastructureProtocols.swift ProofKit/Supabase/SupabaseInfrastructureService.swift ProofKit/AI/AITaskRouter.swift ProofKit/AI/AIService.swift supabase/functions/README.md tasks/todo.md
```

Passed trailing whitespace check:

```bash
rg "[ \t]+$" -n supabase/functions/ai-proxy/index.ts ProofKit/Supabase/SupabaseInfrastructureModels.swift ProofKit/Supabase/SupabaseInfrastructureProtocols.swift ProofKit/Supabase/SupabaseInfrastructureService.swift ProofKit/AI/AITaskRouter.swift ProofKit/AI/AIService.swift supabase/functions/README.md tasks/todo.md
```

Passed static E2E guardrails:

```bash
node --test tests/e2e/proofly-ai-e2e.test.mjs
```

Backend/Edge subtests were skipped because `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` were not present in the shell.

Passed focused Swift build:

```bash
xcodebuild -quiet -jobs 1 -project ProofKit.xcodeproj -scheme ProofKit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .tmp/ProofKitDerivedData-ai-proxy-stream ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

The build emitted only the existing simulator metadata warning and known PostHog/libwebp macro warning.

Not run:

```bash
deno check supabase/functions/ai-proxy/index.ts
```

Reason: `deno` is not installed in this local shell.

## Follow-Up Checklist

- Configure production `ANTHROPIC_AUTH_TOKEN`.
- Confirm whether `ANTHROPIC_BASE_URL` should be explicitly set to `https://code.anyxml.com` or rely on the default.
- Deploy `ai-proxy`.
- Re-inspect the deployed function and confirm the remote source includes:
  - `ANTHROPIC_AUTH_TOKEN`
  - `https://code.anyxml.com`
  - `streamAnthropicResponse`
  - `insufficient_ai_credits` with status `402`
- Run a signed-in test request from the app or a controlled HTTP client.
- Confirm successful runs create finalized ledger rows and failed provider runs refund reservations.
