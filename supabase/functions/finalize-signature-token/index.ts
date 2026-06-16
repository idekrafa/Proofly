import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { isSHA256Hex, optionalUUID, requiredString } from "../_shared/signature.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { user } = await requireUser(req);
    const body = await req.json();
    const validationToken = requiredString(body.validationToken, "validationToken", 80).toUpperCase();
    const signedPDFSHA256 = requiredString(body.signedPDFSHA256, "signedPDFSHA256", 64).toLowerCase();
    if (!isSHA256Hex(signedPDFSHA256)) throw new Error("signedPDFSHA256_invalid");
    const exportID = optionalUUID(body.exportID, "exportID");
    if (!exportID) throw new Error("exportID_required");

    const admin = serviceClient();
    const { data: existing, error: selectError } = await admin
      .from("pdf_signature_validations")
      .select("validation_token, user_id, status, signed_export_id, signed_pdf_sha256, algorithm, key_version, issued_at, signed_at, finalized_at")
      .eq("validation_token", validationToken)
      .maybeSingle();
    if (selectError) throw selectError;
    if (!existing) {
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
    if (existing.user_id !== user.id) throw new Error("token_not_owned_by_user");
    if (existing.status === "revoked") throw new Error("token_revoked");
    if (existing.status === "finalized") {
      if (existing.signed_export_id === exportID && existing.signed_pdf_sha256 === signedPDFSHA256) {
        return jsonResponse({
          valid: true,
          status: existing.status,
          validationToken,
          issuedAt: existing.issued_at,
          signedAt: existing.signed_at,
          finalizedAt: existing.finalized_at,
          algorithm: existing.algorithm,
          keyVersion: existing.key_version,
          reason: null,
        });
      }
      throw new Error("token_already_finalized");
    }
    if (existing.status !== "issued") throw new Error("token_not_issuable");

    const finalizedAt = new Date().toISOString();
    const { data: updated, error: updateError } = await admin
      .from("pdf_signature_validations")
      .update({
        status: "finalized",
        signed_export_id: exportID,
        signed_pdf_sha256: signedPDFSHA256,
        finalized_at: finalizedAt,
        updated_at: finalizedAt,
      })
      .eq("validation_token", validationToken)
      .eq("user_id", user.id)
      .eq("status", "issued")
      .select("status, algorithm, key_version, issued_at, signed_at, finalized_at")
      .single();
    if (updateError) throw updateError;

    return jsonResponse({
      valid: true,
      status: updated.status,
      validationToken,
      issuedAt: updated.issued_at,
      signedAt: updated.signed_at,
      finalizedAt: updated.finalized_at,
      algorithm: updated.algorithm,
      keyVersion: updated.key_version,
      reason: null,
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, { status: 400 });
  }
});
