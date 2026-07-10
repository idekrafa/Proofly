# Proofly E2E

> AI was removed from the product on 2026-07-09 (Edge Functions, credit
> metering, and all in-app AI features). The AI e2e suite and its synthetic
> fixtures were retired with it.

Remaining coverage:

- `manual-sandbox-purchase-checklist.md` — manual App Store sandbox purchase
  validation for the subscription (trial, weekly, monthly, cancellation,
  refund) against `subscription_accounts`.

Automated suites for the signature features (`create-signature-token`,
`sign-request`, `verify-signature-token`, …) do not exist yet; see
`docs/claude-code-pdf-signature-context.md` for the manual verification steps.
