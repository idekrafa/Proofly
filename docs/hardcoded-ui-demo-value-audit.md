# Hardcoded UI/Demo Value Audit

> **Note (2026-07-09):** AI was removed from Proofly entirely — the `ai-proxy`,
> `ai-credit-balance`, and `ai-credit-reserve` Edge Functions, the credit
> tables/RPCs (migration `20260709120000_remove_ai_credit_system.sql`), and all
> in-app AI features (Timeline Summary, Packet Polish, Clean Up Note). The Pro
> plan no longer includes AI services. This document is historical.

Date: May 8, 2026

## Executive summary

ProofKit was audited for hardcoded UI/demo values that could make production screens look fake or user-specific. The priority issue, `Welcome back, Rafael`, was removed. The homepage greeting now uses authenticated Supabase/profile/auth metadata when available and falls back safely when profile data is missing or still loading.

The homepage and case-list cards now use real local case/proof/export/readiness state instead of hardcoded or heuristic demo values:

- Authenticated user name from Supabase/profile/auth metadata.
- Case title from `CaseFile.userTitle`.
- Case category from `CaseReadinessCalculator` normalized category output.
- Proof count from actual `EvidenceItem` relationships.
- Readiness score and next step from `CaseReadinessCalculator`.
- Updated date from `CaseFile.updatedAt`.
- Export/generated packet state from `ExportPacket` data.
- Plan and AI-credit UI from entitlement/AI-credit service state where available.

## Audit scope

The Swift app was searched for the requested hardcoded/demo values and related UI patterns:

- `Rafael`
- `Welcome back`
- `SP`
- `School proof packet`
- `Other`
- `70%`, `73%`, and static progress-like values
- `Current step`
- `Updated today`
- `2 proof items` / `2 evidence items`
- user-facing `evidence items`
- hardcoded plan names, prices, and AI credits
- hardcoded page counts and export states

Intentional static labels were preserved, including:

- `Add Proof`
- `Manage Case`
- `New Case`
- `Overview`
- `Cases`
- `Vault`
- `Settings`

## Source-of-truth mapping

| UI field | Source now used | Fallback behavior |
| --- | --- | --- |
| Homepage greeting | `ProofKitAccountSession.profileFirstName`, derived from Supabase/profile/auth metadata | `Welcome back` when no usable name exists |
| First name | Explicit first-name metadata first, then first token of display name | No name displayed if missing/invalid |
| Case title | `CaseFile.userTitle` via display-title helper | `Untitled Case` when blank |
| Case category | `CaseReadinessCalculator.calculate(for:).category.displayName` | `Other` only for missing/unknown category fallback |
| Proof count | `CaseReadinessResult.counts.proofItemCount` / actual `evidenceItems.count` | `0 proof items` naturally from count formatting |
| Readiness score | `CaseReadinessCalculator` | `0% ready` based on empty/early case state |
| Next step | `CaseReadinessResult.nextStepLabel` | Calculator returns safe next-action labels |
| Updated label | `CaseFile.updatedAt` | `Updated today` if today, otherwise short date; `updatedAt` is non-optional in current SwiftData model |
| Export readiness | `missingExportItems`, estimated page count, and current export access | Missing-item guidance when not ready |
| Generated export details | Latest `ExportPacket` and local PDF URL if present | `Unavailable` for missing persisted page count/file size fields |
| Plan/credits | `PaywallServicing.currentEntitlement()` and `AICreditTrackingServicing.fetchAICreditBalance()` | Included-plan fallback when backend credit status is unavailable |

## User display helper

Added:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Utilities/UserDisplayName.swift`

Behavior:

1. If a sanitized explicit first name exists, render `Welcome back, {firstName}`.
2. Else if a sanitized display name exists, derive the first token and render `Welcome back, {firstName}`.
3. Else render `Welcome back`.
4. Name strings containing email-like `@` values, blank strings, or strings without letters are rejected for UI display.

Session support was added in:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Supabase/SupabaseInfrastructureModels.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Supabase/SupabaseInfrastructureService.swift`

The Supabase/auth name lookup checks common metadata keys such as:

- `first_name`
- `firstName`
- `given_name`
- `givenName`
- `display_name`
- `displayName`
- `full_name`
- `fullName`
- `name`
- `preferred_username`
- `user_name`
- `username`

Identity metadata is also checked when auth user metadata does not contain a usable name.

## Key app changes

### Homepage greeting

Updated:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/HomeView.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/ContentView.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/ProofKitRootView.swift`

Before:

```swift
Welcome back,
Rafael
```

After:

```swift
accountSession?.welcomeBackGreeting ?? "Welcome back"
```

This keeps the greeting working when profile/session data is unavailable.

### Homepage featured case card

Updated:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/HomeView.swift`

The featured card now uses:

- `CaseReadinessCalculator.calculate(for:)`
- `readiness.score`
- `readiness.nextStepLabel`
- `readiness.category.displayName`
- `readiness.counts.generatedExportCount`
- actual `CaseFile` title/status/thumbnail data

The previous home-specific heuristic progress calculation was removed.

### Homepage case rows and Cases tab cards

Updated:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/HomeView.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/CasesView.swift`

Rows/cards now display:

```text
{normalizedCategory} · {actualProofCount} · {updatedDate}
{readinessScore}% ready · {nextStep}
```

Examples of dynamic output:

```text
Apartment · 3 proof items · Updated today
78% ready · Next: Check timeline
```

```text
Other · 0 proof items · Updated May 8, 2026
14% ready · Next: Add proof
```

`Other` in this context is reserved for missing/unknown category fallback.

### Case category labels

Updated:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Models/ProofKitEnums.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Services/CaseReadinessCalculator.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/CreateCaseFlowView.swift`

Changes:

- User-selectable `Other` case/proof/attachment labels were renamed to `Something Else` / `Something else`.
- `CaseReadinessCalculator` still uses `Other` only when the category is missing or unknown.
- Normalized categories such as Apartment, Refund, Work, School, Insurance, Small Claims, Family, and Immigration are displayed from calculator output.

### Starter school case title

Updated:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/OnboardingPurposeView.swift`

The exact demo-looking starter title `School proof packet` was removed and replaced with a generic dynamic starter title pattern for school/college onboarding.

### Export copy and page counts

Updated:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/ExportPreviewView.swift`

The almost-ready export state no longer always says to add one proof item. It now reflects the first actual missing export item:

```swift
"\(firstMissingItem.title), then Rook can pack your timeline into a PDF."
```

Generated export details use persisted `ExportPacket` state:

- generated date
- page count
- file size
- local PDF URL

Ready-but-not-generated export copy continues to use an estimated page count based on current case contents.

### Plan and AI-credit UI

Updated:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Views/AICreditStatusCard.swift`
- Existing entitlement/paywall services remain the source of truth.

Removed an unused static local-only AI-credit snapshot containing hardcoded `Free`/`5` values. Runtime plan/credit display continues to use:

- `services.paywall.currentEntitlement()`
- `services.aiCredits.fetchAICreditBalance()` when configured
- plan-included fallback when credit status cannot be refreshed

## Supabase/profile support

Profile display-name support is additive.

Relevant files:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Supabase/SupabaseInfrastructureProtocols.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Supabase/SupabaseInfrastructureModels.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Supabase/SupabaseInfrastructureService.swift`
- `/Volumes/MacintoshSSD/ProofKit/supabase/migrations/20260508120000_add_profile_display_name.sql`

The profile registration RPC now accepts a display name and returns `profile_display_name`. Existing profile rows are preserved; the display name is inserted for new profiles or filled only when an existing profile name is empty.

## Analytics privacy

Displaying a first name locally in the UI is allowed. The audit did not add name/email/case-title analytics.

The existing readiness analytics path remains privacy-safe:

- uses hashed case/user IDs
- includes safe metadata such as score, bucket, category, counts, booleans, subscription tier, and case age
- does not include names, emails, raw case titles, OCR text, notes, screenshots, documents, filenames, local file paths, or attachment contents

Relevant files:

- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Services/AnalyticsTracking.swift`
- `/Volumes/MacintoshSSD/ProofKit/ProofKit/Services/CaseReadinessCalculator.swift`

## Verification performed

### Demo/hardcoded string audit

Passed:

```sh
rg -n --glob '*.swift' 'Rafael|School proof packet|\bSP\b|Current step|2 proof items|2 evidence items|evidence items' ProofKit
```

Result: no matches.

Passed:

```sh
rg -n --glob '*.swift' '"Other"' ProofKit
```

Result: only the `CaseReadinessCalculator` missing/unknown category fallback remains.

### Static percentage audit

Remaining `0.70` / `0.73` matches are not UI/demo progress values:

- date-detection confidence constant
- color opacity constant
- PDF divider color constant

No hardcoded `70%` or `73%` UI progress strings remain.

### Source hygiene

Passed:

```sh
git diff --check
```

Passed trailing-whitespace checks for touched Swift, Supabase migration, Markdown, and task files.

### Build

Passed:

```sh
xcodebuild -quiet \
  -project ProofKit.xcodeproj \
  -scheme ProofKit \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .tmp/ProofKitDerivedData-hardcoded-ui-audit \
  build
```

## Acceptance criteria status

- [x] No hardcoded `Rafael` appears in app UI.
- [x] Homepage greeting uses authenticated Supabase/profile/auth user data.
- [x] Greeting works when profile data is missing or loading.
- [x] Case cards use real case title.
- [x] Case cards use normalized case category display name.
- [x] Case cards use actual proof counts.
- [x] Case cards use readiness score and next step from `CaseReadinessCalculator`.
- [x] Case cards use `updatedAt` for updated labels.
- [x] `Other` appears only as a missing/unknown fallback.
- [x] Export/page-count states use generated or estimated packet state.
- [x] Subscription/credit UI uses entitlement/backend state where available.
- [x] No private user data is sent to analytics.

## Data-loss assessment

This audit did not change local SwiftData persistence.

No changes were made to:

- SwiftData `@Model` classes
- persisted properties
- relationships
- delete rules
- identifiers
- local SwiftData schema
- model-container configuration
- account-scoped SwiftData storage paths
- local proof file storage paths
- sign-in/sign-out local data deletion behavior
- cache cleanup behavior

The case-card and greeting changes read existing session/profile metadata and existing `CaseFile`, `EvidenceItem`, and `ExportPacket` state only. They do not reset, recreate, relocate, delete, or migrate local user data.

The Supabase profile change is additive and server-side. It does not modify the local SwiftData store. Local migration behavior was not applicable because no local persistence schema or storage path changed.
