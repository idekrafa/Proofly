# Manual Sandbox Purchase E2E Checklist

Use only synthetic cases and a dedicated sandbox tester.

> Updated 2026-07-09: AI was removed from the product entirely. Pro covers
> unlimited cases/proof, clean exports, and signature features; there is
> nothing AI-related to verify.

## Preflight

- Confirm the build points at the intended Supabase project.
- Confirm RevenueCat uses sandbox products for Proofly Weekly Pro and Monthly Pro.
- Confirm the RevenueCat webhook targets `revenuecat-webhook`.
- Confirm the webhook authorization value is configured in Supabase secrets and RevenueCat.
- Confirm no real screenshots, OCR, proof files, case titles, or notes are used.

## Trial To Weekly

- Create a fresh sandbox account.
- Start the Weekly Pro free trial from the paywall.
- Verify paywall copy shows full Pro trial access, then $3.99/week after trial.
- Verify Supabase `subscription_accounts` has:
  - `plan = trial_weekly_intro`
  - `status = trialing`
  - `renews_into_plan = weekly_pro`
  - `unlimited_cases = true`

## Weekly Purchase

- Complete or simulate renewal into Weekly Pro.
- Verify `plan = weekly_pro` and active status.
- Verify local Pro benefits remain available.

## Monthly Purchase

- Purchase Monthly Pro with a fresh synthetic sandbox user.
- Verify `plan = monthly_pro` and active status.

## Cancellation, Expiration, Refund

- Cancel or expire the sandbox subscription.
- Verify status maps to `expired` or `cancelled` as expected.
- Process a refund/revoke event if available.
- Verify status maps to `revoked_or_refunded`.

## Privacy Checks

- Inspect `subscription_accounts`.
- Confirm no OCR text, screenshots, image/PDF bytes, filenames, local paths, case titles, or user notes are stored.

## Report

- Record sandbox-only manual findings in release notes without including sensitive account tokens or user data.
