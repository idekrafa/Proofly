import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requiredString } from "../_shared/signature.ts";
import {
  base64ToBytes,
  isExpired,
  MAX_SIGNATURE_IMAGE_BYTES,
  parseSignaturePosition,
  sha256HexOfBytes,
  SIGNATURE_REQUEST_BUCKET,
  type SignatureRequestRow,
  tokenLookupHash,
} from "../_shared/signatureRequest.ts";

const CONSENT_TEXT =
  "I agree to sign this document electronically. I understand my drawn signature, name, and signing details will be recorded and shared with the requester.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    if (req.method === "GET") return await handleGet(req);
    if (req.method === "POST") return await handleSubmit(req);
    return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, { status: 400 });
  }
});

async function handleGet(req: Request): Promise<Response> {
  const url = new URL(req.url);
  // The signing page is hosted on the marketing domain (supabase.co refuses to render
  // HTML), so it reads request state through `format=json` and streams the document
  // through `asset=pdf`; the HTML branches below only serve legacy links.
  const wantsJSON = url.searchParams.get("format") === "json";
  const token = url.searchParams.get("token")?.trim() ?? "";
  if (!token) {
    if (wantsJSON) return jsonResponse({ error: "missing_token" }, { status: 400 });
    return htmlResponse(statusPage("Invalid link", "This signing link is missing its token."), 400);
  }

  const row = await findRequest(token);
  if (!row) {
    if (wantsJSON) return jsonResponse({ error: "not_found" }, { status: 404 });
    return htmlResponse(statusPage("Link not found", "This signing link does not exist or was replaced by a newer one."), 404);
  }

  if (url.searchParams.get("asset") === "pdf") {
    if (!isViewable(row)) return htmlResponse(statusPage("Unavailable", "This document is no longer available."), 410);
    const admin = serviceClient();
    const download = await admin.storage.from(SIGNATURE_REQUEST_BUCKET).download(row.pdf_storage_path);
    if (download.error || !download.data) return jsonResponse({ error: "pdf_unavailable" }, { status: 404 });
    return new Response(download.data, {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="document.pdf"`,
        "Cache-Control": "no-store",
      },
    });
  }

  if (row.status === "cancelled") {
    if (wantsJSON) return jsonResponse({ status: "cancelled" });
    return htmlResponse(statusPage("Request cancelled", "The requester cancelled this signature request."));
  }
  if (row.status === "signed") {
    if (wantsJSON) return jsonResponse({ status: "signed", signedAt: row.signed_at });
    return htmlResponse(statusPage("Already signed", "This document was already signed. Nothing else is needed."));
  }
  if (row.status === "expired" || isExpired(row)) {
    await markExpired(row);
    if (wantsJSON) return jsonResponse({ status: "expired" });
    return htmlResponse(statusPage("Link expired", "This signing link has expired. Ask the requester to send a new one."));
  }

  if (wantsJSON) {
    return jsonResponse({
      status: "pending",
      documentTitle: row.document_title,
      requesterName: row.requester_name,
      message: row.message,
      expiresAt: row.expires_at,
      consentText: CONSENT_TEXT,
    });
  }

  return htmlResponse(signingPage(row, token));
}

async function handleSubmit(req: Request): Promise<Response> {
  const body = await req.json();
  const token = requiredString(body.token, "token", 128);
  const signerName = requiredString(body.signerName, "signerName", 120);
  if (body.consent !== true) throw new Error("consent_required");
  const signatureImageBase64 = requiredString(body.signatureImageBase64, "signatureImageBase64", 4 * 1024 * 1024);
  const signaturePosition = parseSignaturePosition(body.signaturePosition);

  const row = await findRequest(token);
  if (!row) throw new Error("request_not_found");
  if (row.status === "cancelled") throw new Error("request_cancelled");
  if (row.status === "signed") throw new Error("already_signed");
  if (row.status === "expired" || isExpired(row)) {
    await markExpired(row);
    throw new Error("request_expired");
  }

  const cleanedBase64 = signatureImageBase64.replace(/^data:image\/png;base64,/, "");
  const imageBytes = base64ToBytes(cleanedBase64);
  if (imageBytes.byteLength === 0) throw new Error("signature_image_empty");
  if (imageBytes.byteLength > MAX_SIGNATURE_IMAGE_BYTES) throw new Error("signature_image_too_large");
  // PNG magic bytes — the canvas always exports PNG; reject anything else.
  if (!(imageBytes[0] === 0x89 && imageBytes[1] === 0x50 && imageBytes[2] === 0x4e && imageBytes[3] === 0x47)) {
    throw new Error("signature_image_invalid");
  }
  const signatureImageSHA256 = await sha256HexOfBytes(imageBytes);
  const signatureImagePath = `${row.user_id}/${row.id}/signature.png`;

  const admin = serviceClient();
  const upload = await admin.storage.from(SIGNATURE_REQUEST_BUCKET).upload(signatureImagePath, imageBytes, {
    contentType: "image/png",
    upsert: true,
  });
  if (upload.error) throw upload.error;

  const signedAt = new Date().toISOString();
  const signerIP = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;
  const signerUserAgent = req.headers.get("user-agent")?.slice(0, 400) ?? null;

  const { data: updated, error } = await admin
    .from("pdf_signature_requests")
    .update({
      status: "signed",
      signer_name: signerName,
      signer_ip: signerIP,
      signer_user_agent: signerUserAgent,
      signature_image_path: signatureImagePath,
      signature_image_sha256: signatureImageSHA256,
      signature_position_page: signaturePosition?.pageIndex ?? null,
      signature_position_x: signaturePosition?.x ?? null,
      signature_position_y: signaturePosition?.y ?? null,
      consent_text: CONSENT_TEXT,
      signed_at: signedAt,
      updated_at: signedAt,
    })
    .eq("id", row.id)
    .eq("status", "pending")
    .select("id");
  if (error) throw error;
  if (!updated || updated.length === 0) throw new Error("already_signed");

  return jsonResponse({ signed: true, signedAt });
}

async function findRequest(token: string): Promise<SignatureRequestRow | null> {
  const admin = serviceClient();
  const tokenSHA256 = await tokenLookupHash(token);
  const { data, error } = await admin
    .from("pdf_signature_requests")
    .select("*")
    .eq("request_token_sha256", tokenSHA256)
    .maybeSingle();
  if (error) throw error;
  return (data as SignatureRequestRow | null) ?? null;
}

function isViewable(row: SignatureRequestRow): boolean {
  if (row.status === "pending") return !isExpired(row);
  return row.status === "signed";
}

async function markExpired(row: SignatureRequestRow): Promise<void> {
  if (row.status !== "pending") return;
  const admin = serviceClient();
  await admin
    .from("pdf_signature_requests")
    .update({ status: "expired", updated_at: new Date().toISOString() })
    .eq("id", row.id)
    .eq("status", "pending");
}

function htmlResponse(html: string, status = 200): Response {
  return new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function pageShell(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escapeHTML(title)}</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f4f4f0; color: #17171a; padding: 16px; }
  .wrap { max-width: 560px; margin: 0 auto; }
  .card { background: #fff; border: 1px solid #e2e2da; border-radius: 16px; padding: 20px; margin-bottom: 14px; }
  h1 { font-size: 20px; margin-bottom: 6px; }
  p.sub { color: #5b5b57; font-size: 14px; line-height: 1.45; }
  .status-icon { font-size: 34px; margin-bottom: 10px; }
</style>
</head>
<body>
<div class="wrap">
  ${body}
</div>
</body>
</html>`;
}

function statusPage(title: string, detail: string): string {
  return pageShell(title, `
  <div class="card">
    <div class="status-icon">✳️</div>
    <h1>${escapeHTML(title)}</h1>
    <p class="sub">${escapeHTML(detail)}</p>
  </div>`);
}

function signingPage(row: SignatureRequestRow, token: string): string {
  // Legacy path only: supabase.co cannot render HTML, so direct links to this
  // function show raw source. Real signing happens on the hosted page; this
  // fallback just points the signer at the share URL contents.
  return statusPage(
    `Sign ${row.document_title}`,
    `Open this link in a browser at https://www.proofly.me/sign?token=${encodeURIComponent(token)} to review and sign the document.`,
  );
}
