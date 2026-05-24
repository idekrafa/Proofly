# Manual Sandbox Purchase E2E Checklist

Use only synthetic cases and a dedicated sandbox tester.

## Preflight

- Confirm the build points at the intended Supabase project.
- Confirm RevenueCat uses sandbox products for Proofly Weekly Pro and Monthly Pro.
- Confirm the RevenueCat webhook targets `revenuecat-webhook`.
- Confirm the webhook authorization value is configured in Supabase secrets and RevenueCat.
- Confirm no real screenshots, OCR, proof files, case titles, or notes are used.

## Trial To Weekly

- Create a fresh sandbox account.
- Start the Weekly Pro free trial from the paywall.
- Verify paywall copy shows full Pro trial access, 3 AI credits during trial, then $3.99/week after trial.
- Verify Supabase `subscription_accounts` has:
  - `plan = trial_weekly_intro`
  - `status = trialing`
  - `renews_into_plan = weekly_pro`
  - `unlimited_cases = true`
  - `ai_credit_allowance = 3`
- Verify `ai_credit_balances.credits_granted = 3`.
- Run one synthetic Clean Up Note and one synthetic Timeline Summary only if live AI spend is explicitly approved.
- Verify credits decrease by 1 and 2, respectively, and ledger rows store metadata only.

## Weekly Purchase

- Complete or simulate renewal into Weekly Pro.
- Verify `plan = weekly_pro`, active status, and `credits_granted = 15`.
- Verify local non-AI Pro benefits remain available.

## Monthly Purchase

- Purchase Monthly Pro with a fresh synthetic sandbox user.
- Verify `plan = monthly_pro`, active status, and `credits_granted = 75`.

## Cancellation, Expiration, Refund

- Cancel or expire the sandbox subscription.
- Verify status maps to `expired` or `cancelled` as expected.
- Verify AI credits are zero or unusable once entitlement is inactive.
- Process a refund/revoke event if available.
- Verify status maps to `revoked_or_refunded` and AI credits are zero or unusable.

## Privacy Checks

- Inspect `ai_usage_ledger`, `ai_credit_balances`, and `subscription_accounts`.
- Confirm no OCR text, screenshots, image/PDF bytes, filenames, local paths, case titles, user notes, prompts, or AI outputs are stored.
- Confirm AI output remains separate from original proof/OCR/user-note fields in the app.

## Report

- Save the automated `test-results/ai-usage-cost-report.*` artifacts from the closest matching E2E run.
- Record sandbox-only manual findings in release notes without including sensitive account tokens or user data.
