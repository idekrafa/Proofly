# Ask Sign: Remote Counterparty Signature via Shareable Link

Last updated: 2026-07-06

Ask Sign lets a Proofly user send a generated PDF to another party for electronic signature through a link shareable on any channel (WhatsApp, Instagram, email, SMS, …). The counterparty signs first in the browser; the owner then adds their own signature in the app and exports the final PDF containing both.

## User flow

1. Owner generates a PDF packet on the export screen.
2. Owner taps **Ask Sign** (PRO-gated, same paywall as Sign) → `AskSignView` sheet: optional requester name + message, counterparty signature page/placement, link expiry (3/7/14/30 days).
3. App uploads the PDF and creates the request → gets a share link → owner shares it via the system share sheet, copies it, or has the counterparty scan the QR code shown in the app (the QR encodes the same share URL, so scanning opens the signing page in the counterparty's browser — no app install needed).
4. Counterparty opens the link in any browser: sees the PDF (pdf.js preview + open-in-tab fallback), enters their full name, draws a signature, checks the electronic-signature consent box, submits.
5. Back in the app, the Ask Sign card on the export screen shows **Signed** with the signer's name and signature thumbnail (auto-refreshes on screen load, or via Check).
6. Owner adds their own signature (existing Sign flow) and taps Generate — the new PDF stamps both signatures, and PDF document info carries `ProoflyCounterpartySignerName`, `ProoflyCounterpartySignedAt`, `ProoflyCounterpartyRequestID`, `ProoflyCounterpartySignatureImageSHA256`.

## Backend

Migration `supabase/migrations/20260706120000_pdf_signature_requests.sql`:

- Table `public.pdf_signature_requests` — status `pending | signed | cancelled | expired`, raw token + `request_token_sha256` (unique lookup index), document title/message, page/placement, PDF storage path + SHA-256, signer name/IP/user-agent, signature image path + SHA-256, consent text, expiry, timestamps. RLS: owner read only; writes go through Edge Functions with the service role.
- Private Storage bucket `signature-requests` — holds `<user_id>/<request_id>/document.pdf` and `signature.png`.

Edge Functions (in `supabase/functions/`, shared helpers in `_shared/signatureRequest.ts`):

- `create-signature-request` (JWT required) — validates inputs, verifies the uploaded PDF's SHA-256, enforces 15 MB limit, uploads to storage, cancels prior pending requests for the same case (one active link per case), inserts the row with a random 192-bit URL token, returns `shareURL`.
- `sign-request` (public, `verify_jwt = false`) — GET serves the mobile-first HTML signing page (XSS-escaped, `noindex`, no-store); GET with `asset=pdf` streams the PDF; POST validates token/status/expiry, requires consent + name, verifies the PNG magic bytes and 2 MB limit, stores the signature image, and atomically flips `pending → signed` with signer IP/user-agent audit fields. Expired links are lazily marked `expired`.
- `signature-request-status` (JWT required) — returns the owner's latest request by case (or by request ID), including the signature image base64 when signed; `cancel: true` cancels a pending request.

Share URL defaults to `${SUPABASE_URL}/functions/v1/sign-request?token=…`; set the optional `PROOFKIT_SIGN_REQUEST_BASE_URL` secret to serve from a custom domain. No other new secrets are required.

## iOS

- `SignatureRequestServicing` (`SupabaseInfrastructureProtocols.swift`) implemented by `SupabaseInfrastructureService`, exposed as `services.signatureRequests`; models in `SupabaseInfrastructureModels.swift`; function names configurable via `PROOFKIT_SUPABASE_FN_CREATE_SIGNATURE_REQUEST` / `PROOFKIT_SUPABASE_FN_SIGNATURE_REQUEST_STATUS`.
- `PDFExportRequest.counterpartySignatureStamp` (`PDFCounterpartySignatureStamp`) draws the counterparty signature with the caption "Signed by <name> · Proofly Ask Sign <request id>" using the same placement engine as the owner stamp.
- `AskSignView.swift` — creation sheet + share/copy link UI + scannable QR code of the share URL (rendered by `ProofKitQRCodeView.swift`, also shown on the pending Ask Sign card in `ExportPreviewView`).
- `ExportPreviewView.swift` — Ask Sign button in the generated-packet actions, status card (pending: share/check/cancel; signed: signer + thumbnail), automatic inclusion of the counterparty stamp on the next PRO generate.

No SwiftData schema changes; request state lives server-side and is re-fetched by case ID.

## Deployment status

Migration applied and all three functions deployed to project `zvwixgdclmrhopsbuqld` on 2026-07-06 via Supabase MCP. Web signing flow verified end-to-end against production (invalid token page, signing page render, consent + signature POST, audit fields written, duplicate-sign rejected).

## Caveats / follow-ups

- The signing page loads pdf.js from cdnjs; if it fails, the page degrades to an "Open PDF" link.
- Counterparty identity is self-attested (name + consent + IP/user-agent audit trail); this is not an identity-verified or ICP-Brasil/gov.br qualified signature. Follow the compliance guidance in `docs/claude-code-pdf-signature-context.md`.
- Consider a scheduled cleanup for expired requests' storage objects.
- Rate limiting on the public `sign-request` endpoint is inherited from Supabase defaults only.
