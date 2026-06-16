import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { isSHA256Hex, requiredString } from "../_shared/signature.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const body = req.method === "GET"
      ? Object.fromEntries(new URL(req.url).searchParams.entries())
      : await req.json();
    const validationToken = requiredString(body.validationToken ?? body.token, "validationToken", 80).toUpperCase();
    const signedPDFSHA256 = body.signedPDFSHA256 == null || body.signedPDFSHA256 === ""
      ? null
      : requiredString(body.signedPDFSHA256, "signedPDFSHA256", 64).toLowerCase();
    if (signedPDFSHA256 && !isSHA256Hex(signedPDFSHA256)) throw new Error("signedPDFSHA256_invalid");

    const admin = serviceClient();
    const { data, error } = await admin
      .from("pdf_signature_validations")
      .select("validation_token, status, signed_pdf_sha256, algorithm, key_version, issued_at, signed_at, finalized_at, revoked_at")
      .eq("validation_token", validationToken)
      .maybeSingle();
    if (error) throw error;

    if (!data) {
      return jsonResponse({
        valid: false,
        status: "missing",
        validationToken,
        issuedAt: null,
        signedAt: null,
        finalizedAt: null,
        algorithm: null,
        keyVersion: null,
        reason: "token_not_found",
      }, { status: 404 });
    }

    let valid = data.status === "finalized";
    let reason = valid ? null : data.status === "revoked" ? "token_revoked" : "token_not_finalized";
    if (valid && signedPDFSHA256 && data.signed_pdf_sha256 !== signedPDFSHA256) {
      valid = false;
      reason = "pdf_hash_mismatch";
    }

    return jsonResponse({
      valid,
      status: data.status,
      validationToken,
      issuedAt: data.issued_at,
      signedAt: data.signed_at,
      finalizedAt: data.finalized_at,
      algorithm: data.algorithm,
      keyVersion: data.key_version,
      reason,
    }, { status: valid ? 200 : 409 });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, { status: 400 });
  }
});
