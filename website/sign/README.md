# Ask Sign signing page (`proofly.me/sign`)

Standalone static page for the Ask Sign flow: the signer previews the PDF,
draws their signature, and taps/drags to place it **anywhere on any page**.
The chosen position (zero-based page index + normalized center, origin
top-left) is stored with the signature and the iOS app stamps the counterparty
signature at exactly that spot on the next generate.

It must be hosted on the `www.proofly.me` Vercel project (the marketing site,
separate repo) because Supabase refuses to render HTML from `*.supabase.co` —
the gateway rewrites `text/html` to `text/plain` and adds a sandbox CSP, so the
signing page cannot be served by the Edge Function directly (and a Vercel
rewrite/proxy to the function does NOT help; the downgraded headers pass
through).

The page is fully self-contained (no build step): it reads `?token=…` from the
URL and talks to the `sign-request` Edge Function for everything else:

- `GET  …/sign-request?token=…&format=json` — request state + metadata
- `GET  …/sign-request?token=…&asset=pdf` — the document (rendered with pdf.js)
- `POST …/sign-request?token=…` — signature image + `signaturePosition {pageIndex, x, y}`

These endpoints send `Access-Control-Allow-Origin: *`, and only HTML is blocked
on `supabase.co`, so cross-origin calls from `proofly.me` work.

If the PDF preview cannot render (old browser, broken page), the page degrades
gracefully: signing works without placement and the app falls back to the
requester's preset page/corner.

## Deploying to the marketing site

1. Copy `index.html` into the site so it is served at `/sign` **before** the SPA
   catch-all. For a Vite site on Vercel: put it at `public/sign/index.html` and
   add to `vercel.json`, above the catch-all rewrite:

   ```json
   { "source": "/sign", "destination": "/sign/index.html" }
   ```

2. Verify `https://www.proofly.me/sign?token=anything` shows the Proofly
   "Link not found" card (not the marketing homepage).

That's it — the Edge Functions (`sign-request` v3, `signature-request-status`
v2, `create-signature-request` v2) are already deployed and already emit
`https://www.proofly.me/sign?token=…` share links/QR codes, and the
`signature_position_*` columns already exist in `pdf_signature_requests`.
The `PROOFKIT_SIGN_REQUEST_BASE_URL` secret can override the base URL for
staging.
