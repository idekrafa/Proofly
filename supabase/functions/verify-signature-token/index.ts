import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { isSHA256Hex, requiredString } from "../_shared/signature.ts";

type VerificationResult = {
  valid: boolean;
  status: string;
  validationToken: string;
  issuedAt: string | null;
  signedAt: string | null;
  finalizedAt: string | null;
  algorithm: string | null;
  keyVersion: string | null;
  reason: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // Browsers (QR code scans) get the authenticity page; API clients keep raw JSON.
  const wantsHTML = req.method === "GET" && (req.headers.get("accept") ?? "").includes("text/html");

  try {
    const body = req.method === "GET"
      ? Object.fromEntries(new URL(req.url).searchParams.entries())
      : await req.json();
    const validationToken = requiredString(body.validationToken ?? body.token, "validationToken", 80).toUpperCase();
    const signedPDFSHA256 = body.signedPDFSHA256 == null || body.signedPDFSHA256 === ""
      ? null
      : requiredString(body.signedPDFSHA256, "signedPDFSHA256", 64).toLowerCase();
    if (signedPDFSHA256 && !isSHA256Hex(signedPDFSHA256)) throw new Error("signedPDFSHA256_invalid");

    const result = await verifyToken(validationToken, signedPDFSHA256);
    const httpStatus = result.status === "missing" ? 404 : result.valid ? 200 : 409;

    if (wantsHTML) return htmlResponse(verificationPage(result), httpStatus);
    return jsonResponse(result, { status: httpStatus });
  } catch (error) {
    if (error instanceof Response) return error;
    const message = error instanceof Error ? error.message : String(error);
    if (wantsHTML) {
      return htmlResponse(
        statusPage("Invalid verification link", "This link is missing a valid Proofly signature token. Scan the QR code on the signed PDF again, or type the link exactly as printed."),
        400,
      );
    }
    return jsonResponse({ error: message }, { status: 400 });
  }
});

async function verifyToken(validationToken: string, signedPDFSHA256: string | null): Promise<VerificationResult> {
  const admin = serviceClient();
  const { data, error } = await admin
    .from("pdf_signature_validations")
    .select("validation_token, status, signed_pdf_sha256, algorithm, key_version, issued_at, signed_at, finalized_at, revoked_at")
    .eq("validation_token", validationToken)
    .maybeSingle();
  if (error) throw error;

  if (!data) {
    return {
      valid: false,
      status: "missing",
      validationToken,
      issuedAt: null,
      signedAt: null,
      finalizedAt: null,
      algorithm: null,
      keyVersion: null,
      reason: "token_not_found",
    };
  }

  let valid = data.status === "finalized";
  let reason = valid ? null : data.status === "revoked" ? "token_revoked" : "token_not_finalized";
  if (valid && signedPDFSHA256 && data.signed_pdf_sha256 !== signedPDFSHA256) {
    valid = false;
    reason = "pdf_hash_mismatch";
  }

  return {
    valid,
    status: data.status,
    validationToken,
    issuedAt: data.issued_at,
    signedAt: data.signed_at,
    finalizedAt: data.finalized_at,
    algorithm: data.algorithm,
    keyVersion: data.key_version,
    reason,
  };
}

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
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

function pageShell(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escapeHTML(title)}</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f4f4f0; color: #17171a; padding: 16px; }
  .wrap { max-width: 560px; margin: 0 auto; }
  .brand { display: flex; align-items: center; gap: 8px; margin: 8px 0 16px; color: #444; font-size: 14px; font-weight: 600; letter-spacing: 0.4px; }
  .brand .dot { width: 10px; height: 10px; border-radius: 3px; background: #29d1c7; }
  .card { background: #fff; border: 1px solid #e2e2da; border-radius: 16px; padding: 20px; margin-bottom: 14px; box-shadow: 0 8px 24px rgba(20,20,30,0.06); }
  h1 { font-size: 20px; margin-bottom: 6px; }
  p.sub { color: #5b5b57; font-size: 14px; line-height: 1.45; }
  .status-icon { font-size: 34px; margin-bottom: 10px; }
  .badge { display: inline-block; margin-bottom: 12px; padding: 6px 12px; border-radius: 999px; font-size: 13px; font-weight: 700; }
  .badge.ok { background: #e2f7f2; color: #0a7f78; }
  .badge.bad { background: #fbe9e9; color: #b02a2a; }
  dl { margin-top: 14px; }
  dl div { display: flex; justify-content: space-between; gap: 12px; padding: 9px 0; border-top: 1px solid #efefe8; font-size: 13px; }
  dt { color: #8a8a82; flex-shrink: 0; }
  dd { color: #17171a; text-align: right; word-break: break-all; }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  .footer { text-align: center; color: #8a8a82; font-size: 12px; margin: 18px 0; line-height: 1.5; }
</style>
</head>
<body>
<div class="wrap">
  <div class="brand"><span class="dot"></span>Proofly · Signature verification</div>
  ${body}
  <div class="footer">Proofly records a cryptographic manifest of every signature it stamps.<br>This page checks the token against that record.</div>
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

function verificationPage(result: VerificationResult): string {
  const heading = result.valid ? "Signature verified" : headingForReason(result.reason);
  const detail = result.valid
    ? "This Proofly signature token is authentic. It was issued when the document was signed and finalized against the exported PDF."
    : detailForReason(result.reason);
  const badge = result.valid
    ? `<span class="badge ok">✓ Authentic</span>`
    : `<span class="badge bad">✕ Not verified</span>`;

  const rows = [
    ["Token", result.validationToken, true],
    ["Status", result.status, false],
    ["Issued", formatDate(result.issuedAt), false],
    ["Signed", formatDate(result.signedAt), false],
    ["Finalized", formatDate(result.finalizedAt), false],
    ["Algorithm", result.algorithm ?? "—", false],
    ["Key version", result.keyVersion ?? "—", false],
  ] as const;

  const detailList = `<dl>${
    rows
      .map(([label, value, mono]) =>
        `<div><dt>${escapeHTML(label)}</dt><dd${mono ? ' class="mono"' : ""}>${escapeHTML(String(value))}</dd></div>`
      )
      .join("")
  }</dl>`;

  return pageShell(heading, `
  <div class="card">
    <div class="status-icon">${result.valid ? "✅" : "⚠️"}</div>
    ${badge}
    <h1>${escapeHTML(heading)}</h1>
    <p class="sub">${escapeHTML(detail)}</p>
    ${detailList}
  </div>`);
}

function headingForReason(reason: string | null): string {
  switch (reason) {
    case "token_not_found":
      return "Token not found";
    case "token_revoked":
      return "Token revoked";
    case "pdf_hash_mismatch":
      return "Document mismatch";
    default:
      return "Not verified";
  }
}

function detailForReason(reason: string | null): string {
  switch (reason) {
    case "token_not_found":
      return "This token does not exist in Proofly's records. The document may have been altered, or the token was typed incorrectly.";
    case "token_revoked":
      return "This token was revoked after it was issued. Treat the signed document as no longer verified.";
    case "pdf_hash_mismatch":
      return "The token is genuine, but the document hash you provided does not match the PDF that was finalized. The file may have been modified after signing.";
    default:
      return "This token was issued but the signed PDF was never finalized, so the signature cannot be verified.";
  }
}

function formatDate(value: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toUTCString();
}
