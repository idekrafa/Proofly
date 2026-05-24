# Supabase MCP Migration Application Report

Date: 2026-05-11  
Project: ProofKit / Proofly  
Supabase project ref: `zvwixgdclmrhopsbuqld`  
Scope: AI subscription/credit database migration analysis, application, hardening, and verification through Supabase MCP.

## 1. Executive summary

We used Supabase MCP to analyze the remote database, apply the AI subscription/credit schema, harden RPC privileges, update Edge Function call paths, and verify the final remote state.

Final state:

- Remote database contains the AI subscription and credit tables.
- Remote migration history is aligned with local migration filenames.
- AI credit balance/reservation RPCs are now service-role-only.
- Edge Functions authenticate the user first, then call service-role-only RPCs with the verified user id.
- RLS is enabled on the new public tables.
- Pricing seed rows exist for six AI features.
- `supabase db push --dry-run --linked` reports `Remote database is up to date`.
- No SwiftData/local iOS persistence schema or store behavior changed.

Edge Functions were **not deployed** during this work.

## 2. Why this was done

The AI subscription implementation had local Supabase migrations and Edge Function scaffolding, but the remote Supabase project still needed:

1. remote schema analysis,
2. safe migration validation,
3. migration application,
4. remote schema/RPC/grant/policy verification,
5. migration-history reconciliation with the local CLI workflow.

The user requested using Supabase MCP to analyze and apply the migration.

## 3. MCP access path used

The normal in-session Supabase MCP tools still returned a stale permission error:

```text
MCP error -32600: You do not have permission to perform this action
```

The configured remote Supabase MCP endpoint was still usable through the already-configured bearer-token transport. A temporary helper under `.tmp/` was used to speak MCP-over-HTTP with `curl`.

Important safety notes:

- No MCP bearer token, OAuth token, session id, or Supabase secret was written into tracked source.
- Temporary MCP request/response artifacts stayed under `.tmp/`.
- The helper avoided printing secrets.
- `.tmp/` files are not part of the deliverable.

## 4. Remote pre-apply analysis

Before applying the AI migration, Supabase MCP was used to inspect:

- migration history,
- public tables,
- installed extensions,
- security advisors,
- performance advisors,
- relevant Supabase docs for public schema/RLS guidance.

Pre-apply remote state:

| Area | Finding |
| --- | --- |
| Migrations | Existing remote migrations were `20260507153000_create_profiles` and `20260508120000_add_profile_display_name`. |
| Public tables | Only `public.profiles` existed. |
| AI tables | `subscription_accounts`, `ai_credit_balances`, `ai_usage_ledger`, and `ai_feature_pricing` did not exist yet. |
| Extensions | `pgcrypto` was already installed in the `extensions` schema. |
| Security advisors | Existing warnings around `proofkit_register_profile` and leaked-password protection. |
| Performance advisors | Existing profile RLS `auth.uid()` initplan warnings. |

## 5. Local SQL/schema changes made before and during apply

### 5.1 Main AI subscription architecture migration

Local file now aligned to remote MCP-created version:

`supabase/migrations/20260511210352_20260511120000_ai_subscription_architecture.sql`

This migration creates:

- `public.subscription_accounts`
- `public.ai_credit_balances`
- `public.ai_usage_ledger`
- `public.ai_feature_pricing`

It also adds:

- indexes for subscription lookup and usage ledger lookup,
- RLS on all new public tables,
- feature-pricing seed rows,
- AI credit balance, reservation, finalization, refund, and subscription-sync RPCs.

Additional hardening included in the final local migration chain:

- RLS policies use `(select auth.uid())` where applicable to avoid per-row auth function re-evaluation.
- AI balance/reserve RPCs use an explicit `p_user_id` argument and are service-role-only.
- Service-only RPCs are not executable by `anon` or `authenticated`.

### 5.2 RPC privilege hardening migration

Local file:

`supabase/migrations/20260511210619_20260511211500_harden_ai_rpc_privileges.sql`

Purpose:

- explicitly revoke broad/default function execute privileges,
- keep `proofkit_register_profile` callable only by signed-in users,
- keep service-only AI/subscription RPCs callable only by `service_role`,
- use conditional `to_regprocedure(...)` checks so the file can replay safely in different local/remote states.

### 5.3 Service-only AI RPC migration

Local file:

`supabase/migrations/20260511211007_20260511213000_make_ai_rpcs_service_only.sql`

Purpose:

- remove old direct authenticated RPC signatures:
  - `proofkit_get_ai_credit_balance()`
  - `proofkit_reserve_ai_credits(text, uuid, text)`
- create service-role-only signatures:
  - `proofkit_get_ai_credit_balance(uuid)`
  - `proofkit_reserve_ai_credits(uuid, text, uuid, text)`
- require Edge Functions to pass the verified Supabase user id.

### 5.4 Profile RLS and AI index optimization migration

Local file:

`supabase/migrations/20260511211008_20260511214000_optimize_profiles_rls_and_ai_indexes.sql`

Purpose:

- add `ai_credit_balances_subscription_account_idx`, covering the foreign key from balances to subscription accounts,
- replace `profiles` RLS policies with `(select auth.uid())` form to satisfy the Supabase performance advisor.

## 6. Remote migrations applied through Supabase MCP

Supabase MCP `apply_migration` created the following remote migration history:

| Remote version | Remote migration name | Local file |
| --- | --- | --- |
| `20260511210352` | `20260511120000_ai_subscription_architecture` | `20260511210352_20260511120000_ai_subscription_architecture.sql` |
| `20260511210619` | `20260511211500_harden_ai_rpc_privileges` | `20260511210619_20260511211500_harden_ai_rpc_privileges.sql` |
| `20260511211007` | `20260511213000_make_ai_rpcs_service_only` | `20260511211007_20260511213000_make_ai_rpcs_service_only.sql` |
| `20260511211008` | `20260511214000_optimize_profiles_rls_and_ai_indexes` | `20260511211008_20260511214000_optimize_profiles_rls_and_ai_indexes.sql` |

Local migration filenames were reconciled to match the remote versions generated by MCP. This keeps `supabase migration list --linked` and future CLI migration workflows aligned.

## 7. Edge Function code changes

The Edge Function code was updated so authenticated client JWTs are used only to identify the user. Reads/mutations against subscription/credit tables now happen with the service-role Edge Function client after `requireUser(...)` verifies the request.

### 7.1 `ai-credit-balance`

File:

`supabase/functions/ai-credit-balance/index.ts`

Changed behavior:

- previously used the authenticated user client to call balance RPC,
- now calls `requireUser(req)`, creates `serviceClient()`, and calls:

```ts
admin.rpc("proofkit_get_ai_credit_balance", {
  p_user_id: user.id,
})
```

### 7.2 `ai-credit-reserve`

File:

`supabase/functions/ai-credit-reserve/index.ts`

Changed behavior:

- previously used the authenticated user client to reserve credits,
- now authenticates the user and calls service-role-only reservation RPC with:

```ts
admin.rpc("proofkit_reserve_ai_credits", {
  p_user_id: user.id,
  p_feature: feature,
  p_case_id: caseID,
  p_idempotency_key: idempotencyKey,
})
```

### 7.3 `ai-proxy`

File:

`supabase/functions/ai-proxy/index.ts`

Changed behavior:

- still requires `userTriggered === true`,
- still sanitizes text-only AI input,
- now reserves credits with service-role-only `proofkit_reserve_ai_credits`,
- finalizes/refunds with service-role RPCs,
- fetches the post-run balance with service-role-only `proofkit_get_ai_credit_balance`.

### 7.4 `purchase-entitlements`

File:

`supabase/functions/purchase-entitlements/index.ts`

Changed behavior:

- authenticates the user with `requireUser(req)`,
- reads `subscription_accounts` through `serviceClient()`,
- filters by `user_id = user.id`,
- returns app-compatible entitlement rows.

### 7.5 Edge Function README

File:

`supabase/functions/README.md`

Updated to document:

- authenticated user JWT requirement,
- service-role-only credit/entitlement table access inside Edge Functions,
- no service-role key exposure to iOS or public clients.

## 8. Documentation updates

Updated:

`docs/proofkit-ai-subscription-implementation.md`

Changes included:

- status now says Supabase database migrations were applied via MCP,
- migration checklist lists the applied migrations,
- AI balance/reservation RPC docs now show `p_user_id` and service-role-only semantics,
- Edge Function descriptions now mention verified user id + service-role calls,
- verification section records MCP and CLI final state,
- recommended next steps were adjusted for MCP/CLI migration-history alignment.

Created this report:

`docs/supabase-mcp-migration-application-report.md`

## 9. Final remote database state verified

### 9.1 Migration history

Supabase MCP and CLI verification show remote and local migrations aligned:

```text
Local          | Remote
---------------|---------------
20260507153000 | 20260507153000
20260508120000 | 20260508120000
20260511210352 | 20260511210352
20260511210619 | 20260511210619
20260511211007 | 20260511211007
20260511211008 | 20260511211008
```

### 9.2 Public tables

Supabase MCP verified these public tables after apply:

| Table | RLS | Rows at verification |
| --- | --- | ---: |
| `public.profiles` | enabled | 4 |
| `public.subscription_accounts` | enabled | 0 |
| `public.ai_credit_balances` | enabled | 0 |
| `public.ai_usage_ledger` | enabled | 0 |
| `public.ai_feature_pricing` | enabled | 6 |

### 9.3 Feature pricing seed rows

Verified `ai_feature_pricing` rows:

| Feature | Credits | Tier | Input cap | Output cap | Enabled |
| --- | ---: | --- | ---: | ---: | --- |
| `ask_ai_case` | 3 | `haiku` | 10000 | 1000 | false |
| `ask_ai_short` | 1 | `haiku` | 3000 | 800 | false |
| `deep_review` | 10 | `haiku` | 60000 | 2500 | true |
| `packet_polish` | 4 | `haiku` | 20000 | 1800 | true |
| `rewrite_note` | 1 | `haiku` | 3000 | 800 | true |
| `timeline_summary` | 2 | `haiku` | 12000 | 1200 | true |

### 9.4 Function privilege matrix

Supabase MCP SQL verification showed:

| Function | Exists | `anon` can execute | `authenticated` can execute | `service_role` can execute |
| --- | --- | --- | --- | --- |
| `proofkit_finalize_ai_usage` | yes | no | no | yes |
| `proofkit_get_ai_credit_balance(uuid)` | yes | no | no | yes |
| `proofkit_refund_ai_reservation` | yes | no | no | yes |
| `proofkit_register_profile` | yes | no | yes | yes |
| `proofkit_reserve_ai_credits(uuid, text, uuid, text)` | yes | no | no | yes |
| `proofkit_sync_subscription_account` | yes | no | no | yes |

Old direct AI RPC signatures no longer exist:

- `proofkit_get_ai_credit_balance()`
- `proofkit_reserve_ai_credits(text, uuid, text)`

### 9.5 Policies and indexes

Verified:

- new AI tables have RLS enabled,
- user-facing read policies exist for own subscription/balance/ledger rows,
- authenticated users can read feature pricing,
- `profiles_select_own` and `profiles_update_own` use `(select auth.uid())`,
- `ai_credit_balances_subscription_account_idx` exists.

## 10. Final advisor results

### 10.1 Security advisor

After fixes, Supabase MCP security advisors reported only:

1. `proofkit_register_profile` is callable by signed-in users as a `SECURITY DEFINER` function.
   - This is intentional for the existing registration/profile bootstrap flow.
   - It is no longer executable by `anon`.
2. Leaked password protection is disabled.
   - This is a dashboard/Auth setting, not a SQL migration issue.
   - Recommended follow-up: enable leaked password protection in Supabase Auth settings.

No AI credit service-role-only RPCs were reported as executable by `anon` or `authenticated` after the hardening migrations.

### 10.2 Performance advisor

After fixes, Supabase MCP performance advisors reported only unused indexes on newly created/empty tables:

- `subscription_accounts_user_status_idx`
- `subscription_accounts_source_event_idx`
- `ai_usage_ledger_user_created_idx`
- `ai_usage_ledger_user_feature_created_idx`
- `ai_credit_balances_subscription_account_idx`

These are expected until production traffic exercises the new tables.

The earlier profile RLS `auth.uid()` initplan warning was addressed.

## 11. Verification commands/results

### 11.1 Supabase MCP validation

Before applying migrations, MCP `execute_sql` was used with `BEGIN ... ROLLBACK` validation for:

- main AI architecture SQL,
- privilege-hardening SQL,
- service-only AI RPC SQL,
- profile RLS/index optimization SQL,
- final full local migration chain.

All rollback validations succeeded.

### 11.2 Supabase MCP apply

MCP `apply_migration` returned success for all four applied migrations.

### 11.3 Supabase MCP final verification

MCP was used to verify:

- migration history,
- public tables,
- RLS status,
- pricing seed rows,
- RPC existence,
- RPC role privileges,
- old RPC signature removal,
- policy definitions,
- indexes,
- final advisors.

### 11.4 Supabase CLI verification

Passed:

```sh
supabase migration list --linked
```

Passed:

```sh
supabase db push --dry-run --linked
```

Final dry-run result:

```text
Remote database is up to date.
```

There was one transient concurrent `supabase migration list --linked` failure while another CLI command was initializing a temporary login role. Retrying the command succeeded.

### 11.5 Repository checks

Passed:

```sh
git diff --check -- ProofKit Config supabase docs tasks/todo.md
```

Passed targeted secret-pattern scan for common Supabase/Anthropic/RevenueCat/PostHog key formats.

Source grep confirmed Edge Functions no longer call ProofKit RPCs through the authenticated Supabase client.

## 12. Files changed or added in this pass

### Added migration files

- `supabase/migrations/20260511210352_20260511120000_ai_subscription_architecture.sql`
- `supabase/migrations/20260511210619_20260511211500_harden_ai_rpc_privileges.sql`
- `supabase/migrations/20260511211007_20260511213000_make_ai_rpcs_service_only.sql`
- `supabase/migrations/20260511211008_20260511214000_optimize_profiles_rls_and_ai_indexes.sql`

### Updated Edge Function files

- `supabase/functions/ai-credit-balance/index.ts`
- `supabase/functions/ai-credit-reserve/index.ts`
- `supabase/functions/ai-proxy/index.ts`
- `supabase/functions/purchase-entitlements/index.ts`
- `supabase/functions/README.md`

### Updated documentation/task files

- `docs/proofkit-ai-subscription-implementation.md`
- `docs/supabase-mcp-migration-application-report.md`
- `tasks/todo.md`
- `tasks/lessons.md` was updated separately after the approval-prompt correction.

### Temporary files

Temporary MCP helper/request/response files were created under `.tmp/`. They are not deliverables and should not be committed.

## 13. What was not done

- Edge Functions were not deployed.
- Supabase Edge Function secrets were not set or changed.
- RevenueCat webhook was not configured remotely.
- Local Supabase Postgres was not started; `supabase migration list --local` remains unverified.
- Deno type-checking was not run because `deno` is not installed locally.
- No SwiftData migration was created because no local SwiftData schema changed.

## 14. Security and privacy notes

- The iOS app never receives or uses `SUPABASE_SERVICE_ROLE_KEY`.
- Service-role operations happen only inside Edge Functions.
- Edge Functions first authenticate the request with the user JWT, then pass the verified user id to service-only RPCs.
- AI ledger tables store accounting/status/token/cost/hash metadata only.
- AI ledger tables do not store prompt bodies, OCR text, screenshots, PDFs, local paths, filenames, case titles, user notes, or AI output.
- The Anthropic API key remains server-side only.
- No secrets were hardcoded into tracked files.

## 15. SwiftData/local-data-loss assessment

This work affected remote Supabase schema and Edge Function source only.

No changes were made to:

- SwiftData model properties,
- SwiftData relationships,
- delete rules,
- identifiers,
- storage paths,
- `ModelContainer` configuration,
- production store reset/recreate logic,
- sign-in/sign-out local storage behavior,
- account-switching local storage behavior.

Existing local user data remains untouched:

- documents,
- imported/generated photos,
- OCR text,
- proof records,
- PDFs,
- progress,
- settings,
- account-scoped local data.

No local SwiftData migration path was needed because the local SwiftData schema was not changed.

## 16. Recommended next steps

1. Set required Supabase Edge Function secrets in Supabase secret management.
2. Install or use Deno/Supabase deploy validation to type-check Edge Functions.
3. Deploy Edge Functions.
4. Configure the RevenueCat webhook to call `revenuecat-webhook`.
5. Enable Supabase Auth leaked-password protection in the dashboard if desired.
6. Run an end-to-end test with a synthetic test user and fake/non-sensitive case data.
7. Monitor Supabase advisors after real traffic to decide whether unused indexes remain useful.
8. Keep future MCP-applied migration filenames aligned with remote migration versions before using CLI migration commands.
