# Claude Code Handoff: Proofly PDF Signatures, Validation Tokens, and Brazil/US Compliance Context

Last updated: 2026-06-23

This document gives Claude Code enough context to continue work on Proofly's PDF signing feature without needing the prior chat history.

## Project Rules That Matter

Read `AGENTS.md` before editing.

The highest-priority local rule is data preservation:

- Proofly stores user-owned data locally with SwiftData.
- Do not reset, wipe, recreate, relocate, or destructively migrate the production SwiftData store.
- Do not remove, rename, or alter SwiftData models/properties/relationships/delete rules/storage paths/model-container configuration unless there is an explicit backward-compatible migration plan.
- Prefer additive changes.
- If persistence is touched, document the data-loss assessment in `tasks/todo.md`.

For this signature work, the intended design is additive:

- Existing generated PDFs remain intact.
- Signing an already generated PDF creates a new signed PDF/export record.
- No SwiftData schema/model/container/storage-path changes should be needed.

## Current Feature Goal

Implement and maintain a PDF signing feature where:

- Only PRO users can actually sign PDFs.
- Free users can see the feature, but trying to sign prompts an upgrade/paywall flow.
- PRO users can draw a signature on a blank canvas.
- The user chooses where the signature is placed in the PDF.
- If a PDF has already been generated, signing it automatically creates a new signed PDF.
- Every signed PDF gets a validation token.
- The token is validated server-side through Supabase.
- The PDF embeds signature metadata that can later be used for validation.
- The implementation should follow strong security practices without overclaiming legal compliance.

## Current App Flow

### Normal/free user flow

Starting from the export screen:

1. User sees the PDF signature controls.
2. User taps the signature control.
3. App checks export/paywall access.
4. If the current plan is not PRO, the app presents the upgrade/paywall flow.
5. No signature canvas is opened.
6. No validation token is issued.
7. No signed PDF is generated.

Relevant files:

- `ProofKit/Views/ExportPreviewView.swift`
- `ProofKit/Services/ServiceContainer.swift`

### PRO user flow before PDF generation

1. User taps the signature control.
2. App confirms PRO access.
3. App opens `SignatureCaptureView`.
4. User draws a signature on a blank PencilKit canvas.
5. User selects:
   - signature page: first page, last page, every page
   - signature placement: drags the signature anywhere on a rendered page preview (free-form only; sent as `custom` with a normalized offset)
6. App hashes the rendered signature image.
7. App calls Supabase Edge Function `create-signature-token`.
8. Supabase returns:
   - visible validation token
   - encrypted manifest
   - manifest HMAC/signature
   - manifest SHA-256
   - algorithm
   - key version
   - optional verification URL
9. App stores this as in-memory `ExportSignatureConfiguration`.
10. When user taps `Generate PDF Packet`, app renders the PDF with the signature stamp and token metadata.
11. App hashes the final rendered signed PDF.
12. App calls Supabase Edge Function `finalize-signature-token`.
13. If finalization succeeds, app inserts the `ExportPacket` into SwiftData.
14. If finalization fails, app shows an error and does not save the export record.

Relevant files:

- `ProofKit/Views/SignatureCaptureView.swift`
- `ProofKit/Views/ExportPreviewView.swift`
- `ProofKit/PDF/PDFExportService.swift`
- `ProofKit/Supabase/SupabaseInfrastructureService.swift`
- `supabase/functions/create-signature-token/index.ts`
- `supabase/functions/finalize-signature-token/index.ts`

### PRO user flow after PDF was already generated

1. User already has a generated PDF.
2. User adds or edits signature.
3. App issues a new server-side validation token.
4. The token manifest includes the source PDF hash when available.
5. App automatically calls the PDF generation path again.
6. A new signed PDF is rendered.
7. App hashes the final signed PDF.
8. App finalizes the token against that exact signed PDF hash.
9. App inserts a new `ExportPacket`.
10. The old generated PDF/export is not overwritten.

## Current PDF Rendering Behavior

PDF rendering is handled by:

- `ProofKit/PDF/PDFExportService.swift`

The request model includes:

- `PDFExportRequest.signatureStamp`

The signature stamp model includes:

- signature image
- target page
- placement
- signed timestamp
- validation token
- encrypted manifest
- manifest signature
- manifest SHA-256
- algorithm
- key version

During PDF export:

1. The export service renders the normal packet.
2. If `signatureStamp` exists, it draws the signature on the selected page(s).
3. It writes visible signature/token text into the PDF.
4. It writes signature metadata into the PDF document info dictionary.

Current metadata keys include:

- `ProoflySignatureToken`
- `ProoflySignatureAlgorithm`
- `ProoflySignatureKeyVersion`
- `ProoflySignatureManifestSHA256`
- `ProoflySignatureManifestSignature`
- `ProoflySignatureEncryptedManifest`

The visible token is not encrypted because a verifier must be able to read/type/scan it. The manifest is encrypted, and the manifest signature/hash provide tamper-evidence.

## Supabase Architecture

### Database table

Migration:

- `supabase/migrations/20260615120500_pdf_signature_validations.sql`

Table:

- `public.pdf_signature_validations`

Important columns:

- `id`
- `user_id`
- `validation_token`
- `token_sha256`
- `status`: `issued`, `finalized`, `revoked`
- `case_id`
- `source_export_id`
- `signed_export_id`
- `source_pdf_sha256`
- `signed_pdf_sha256`
- `signature_image_sha256`
- `signature_page`
- `signature_placement`
- `signed_at`
- `issued_at`
- `finalized_at`
- `revoked_at`
- `app_version`
- `pdf_export_mode`
- `include_statement_placeholder`
- `algorithm`
- `key_version`
- `manifest_sha256`
- `manifest_signature`
- `encrypted_manifest`
- `created_at`
- `updated_at`

RLS:

- RLS is enabled.
- Authenticated users can select their own rows.
- General table privileges are revoked.
- Edge Functions use the service role for insert/update/verification queries.

### Edge Functions

Shared helper:

- `supabase/functions/_shared/signature.ts`

Functions:

- `supabase/functions/create-signature-token/index.ts`
- `supabase/functions/finalize-signature-token/index.ts`
- `supabase/functions/verify-signature-token/index.ts`

Supabase config:

- `supabase/config.toml`

`verify-signature-token` is configured as public:

```toml
[functions.verify-signature-token]
verify_jwt = false
```

`create-signature-token` and `finalize-signature-token` require authenticated users.

### Function responsibilities

#### `create-signature-token`

Requires signed-in user.

Validates:

- case ID
- optional source export ID
- optional source PDF hash
- signature image SHA-256
- signature page allowlist
- signature placement allowlist
- signed timestamp
- app version
- PDF export mode

Creates a canonical JSON manifest containing:

- user ID
- case ID
- source export ID
- source PDF hash
- signature image hash
- page
- placement
- signed timestamp
- app version
- export mode
- statement-placeholder flag
- issued timestamp
- key version
- nonce

Then:

- computes manifest SHA-256
- signs manifest with HMAC-SHA256
- encrypts manifest with AES-GCM
- generates visible validation token
- stores row with status `issued`
- returns token and metadata to the app

#### `finalize-signature-token`

Requires signed-in user.

Validates:

- validation token
- final signed PDF SHA-256
- signed export ID

Then:

- confirms token exists
- confirms token belongs to current user
- rejects revoked tokens
- finalizes issued tokens
- returns success response
- is idempotent only if the same already-finalized export ID and PDF hash are supplied again
- rejects attempts to finalize a token onto a different PDF/export after finalization

#### `verify-signature-token`

Public-safe verification endpoint.

Accepts:

- GET query `token`
- POST JSON `validationToken`
- optional `signedPDFSHA256`

Returns:

- valid true only when token status is `finalized`
- invalid if missing, revoked, not finalized, or PDF hash mismatch
- limited public metadata only

It does not return:

- user ID
- encrypted manifest
- full private audit details

## iOS Service Wiring

Models:

- `ProofKit/Supabase/SupabaseInfrastructureModels.swift`

Protocol:

- `ProofKit/Supabase/SupabaseInfrastructureProtocols.swift`
- `PDFSignatureValidationServicing`

Implementation:

- `ProofKit/Supabase/SupabaseInfrastructureService.swift`

Service container:

- `ProofKit/Services/ServiceContainer.swift`
- Adds `signatureValidation`
- Live container wires it to `SupabaseInfrastructureService`

Function names:

- `ProofKit/Supabase/SupabaseConfiguration.swift`

Environment/config keys:

- `PROOFKIT_SUPABASE_FN_CREATE_SIGNATURE_TOKEN`
- `PROOFKIT_SUPABASE_FN_FINALIZE_SIGNATURE_TOKEN`
- `PROOFKIT_SUPABASE_FN_VERIFY_SIGNATURE_TOKEN`

Defaults:

- `create-signature-token`
- `finalize-signature-token`
- `verify-signature-token`

## Supabase Deployment Steps Still Needed

Apply migration:

```bash
supabase db push --project-ref zvwixgdclmrhopsbuqld
```

Set secrets:

```bash
supabase secrets set \
  PROOFKIT_SIGNATURE_HMAC_KEY="$(openssl rand -base64 48)" \
  PROOFKIT_SIGNATURE_ENCRYPTION_KEY_B64="$(openssl rand -base64 32)" \
  PROOFKIT_SIGNATURE_KEY_VERSION="v1" \
  PROOFKIT_SIGNATURE_VERIFICATION_BASE_URL="https://your-domain.com/signature/verify" \
  --project-ref zvwixgdclmrhopsbuqld
```

Deploy functions:

```bash
supabase functions deploy create-signature-token --project-ref zvwixgdclmrhopsbuqld
supabase functions deploy finalize-signature-token --project-ref zvwixgdclmrhopsbuqld
supabase functions deploy verify-signature-token --project-ref zvwixgdclmrhopsbuqld
```

Confirm:

- `create-signature-token` requires JWT.
- `finalize-signature-token` requires JWT.
- `verify-signature-token` is public because `verify_jwt = false`.

Smoke test:

1. Sign in as a PRO user.
2. Generate a signed PDF.
3. Confirm a row is inserted into `pdf_signature_validations`.
4. Confirm status changes from `issued` to `finalized`.
5. Call `verify-signature-token` with the validation token.
6. Call `verify-signature-token` with token plus final PDF hash.
7. Call it with a wrong PDF hash and confirm invalid response.
8. Confirm a free user cannot open the signature canvas and is routed to upgrade.

Recommended Deno check:

```bash
deno check \
  supabase/functions/create-signature-token/index.ts \
  supabase/functions/finalize-signature-token/index.ts \
  supabase/functions/verify-signature-token/index.ts
```

If Deno is not installed locally, this check will fail with `command not found`.

## Security Model

Current design:

- The final signed PDF is bound to the validation token through `signed_pdf_sha256`.
- The signature drawing is bound through `signature_image_sha256`.
- The original generated PDF can be bound through `source_pdf_sha256` when signing an existing export.
- The manifest is canonicalized before hashing/signing/encryption.
- The manifest is HMAC-SHA256 signed.
- The manifest is AES-GCM encrypted using a 32-byte key from Supabase secrets.
- Key version is stored so future key rotation is possible.
- The public verifier does not expose private manifest data.

Important caveat:

- This is a best-practice application validation/audit trail.
- It is not, by itself, a regulated certificate authority, not an ICP-Brasil qualified signature, and not a legal compliance certification.
- For stricter regulatory environments, consider managed KMS/HSM signing, certificate-based PAdES signing, and legal/security review.

## U.S. Signature Context

High-level product guidance:

- U.S. ESIGN/UETA-style validity usually depends on intent to sign, consent to transact electronically, association of the signature with the record, and ability to retain/access the signed record.
- The Proofly flow should capture clear intent text before signing, such as: "I agree to sign this PDF electronically."
- Keep an audit trail with timestamp, user identity, document hash, final PDF hash, token, IP/device metadata where appropriate, and app version.

Recommended data for U.S. validation:

- legal name
- email and/or phone
- user ID
- timestamp with timezone
- IP address, if available and disclosed
- device/app version
- document hash before signing
- final signed PDF hash
- signature image hash
- validation token
- explicit electronic-signature consent
- audit log of signing steps

## Brazil Signature Context

Brazil has multiple practical levels of electronic signature strength. Product copy should avoid saying every Proofly signature is automatically equivalent to an ICP-Brasil qualified digital signature.

Suggested product modes:

### Proofly Verified Signature

Use for ordinary Proofly evidence packets and private-party records.

Collect:

- full legal name
- email and/or phone
- user ID
- timestamp with timezone
- IP address, if available and disclosed
- device/app version
- document hash before signing
- final signed PDF hash
- signature image hash
- validation token
- explicit electronic-signature consent
- audit log of signing steps

This is an app-native evidence/audit trail. It may be useful as an electronic signature, but it should not be marketed as an ICP-Brasil qualified signature.

### Brazil Strong Signature Mode

For stronger Brazilian acceptance, integrate with one of:

- gov.br electronic signature flow, especially for users with appropriate gov.br identity level.
- ICP-Brasil certificate signing through a qualified/certified provider.
- PAdES signing with certificate metadata embedded into the PDF.

Collect CPF only when Brazil validation mode is selected and only when needed.

If collecting CPF:

- treat it as sensitive personal data from a product-risk perspective, even if legal categories can vary by context
- encrypt at rest
- do not display the full CPF in public PDFs
- consider storing a masked display value and a hash for lookup
- disclose why it is collected
- allow deletion/export according to privacy requirements

Recommended Brazil-specific fields:

- CPF, masked in UI/PDF
- full legal name
- country/jurisdiction
- explicit electronic-signature consent in Portuguese
- gov.br verification result or ICP-Brasil certificate metadata, if used
- certificate subject/issuer/serial, if certificate-based signing is used
- signing policy/version
- final PDF hash
- validation token

Suggested UX:

- Offer signing mode choices:
  - `Proofly Verified`
  - `Brazil gov.br / ICP-Brasil`
- Show a short explanation that gov.br/ICP-Brasil may require identity verification or certificate access.
- For free users, keep the feature visible but gated behind PRO upgrade.

## Product Copy Guidance

Avoid:

- "legally valid everywhere"
- "government-certified signature"
- "ICP-Brasil compliant" unless actually using ICP-Brasil certificate signing
- "guaranteed enforceable"

Safer:

- "Proofly Verified Signature"
- "Includes a validation token and audit metadata"
- "Can be verified against the final PDF hash"
- "For Brazil strong-signature workflows, use gov.br or ICP-Brasil signing"

## Recommended Next Implementation Tasks

1. Add a verification screen/page in the app or website.
2. Let users paste a token and optionally upload/provide a PDF hash.
3. Add a public verification URL route matching `PROOFKIT_SIGNATURE_VERIFICATION_BASE_URL`.
4. Add explicit consent text before opening or completing the signature canvas.
5. Add locale-aware consent text for Brazil/Portuguese.
6. Decide whether CPF collection is needed only for Brazil strong-signature mode.
7. Add a Supabase migration for any additional identity/audit fields only after a privacy review.
8. Consider PAdES/ICP-Brasil provider integration if Proofly needs stronger Brazil legal posture.
9. Add server-side rate limiting or abuse controls for public token verification.
10. Add tests for:
    - free user signature gate
    - PRO token issuance
    - generated signed PDF metadata
    - token finalization
    - verification success
    - verification PDF hash mismatch
    - duplicate finalization with same hash
    - duplicate finalization with different hash rejected

## Verification History

Previously verified locally:

- `git diff --check` passed.
- `xcodebuild -project ProofKit.xcodeproj -scheme ProofKit -configuration Debug -destination 'generic/platform=iOS Simulator' build` passed.

Known gap:

- `deno check` could not be run in the local environment where this was implemented because `deno` was not installed.

Before shipping:

- Re-run the iOS build.
- Run Deno type-checks.
- Deploy Supabase migration/functions to a staging project.
- Test with a real authenticated PRO user.
- Test public verification.
- Get legal/security review before making U.S./Brazil compliance claims.

