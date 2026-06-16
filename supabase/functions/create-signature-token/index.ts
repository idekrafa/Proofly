import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import {
  canonicalJSONString,
  configuredKeyVersion,
  encryptManifest,
  isSHA256Hex,
  makeValidationToken,
  optionalUUID,
  parseDate,
  publicVerificationURL,
  requiredString,
  sha256Hex,
  signManifest,
  type SignatureManifest,
} from "../_shared/signature.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { user } = await requireUser(req);
    const body = await req.json();

    const caseID = optionalUUID(body.caseID, "caseID");
    if (!caseID) throw new Error("caseID_required");
    const exportID = optionalUUID(body.exportID, "exportID");
    const sourcePDFSHA256 = body.sourcePDFSHA256 == null || body.sourcePDFSHA256 === ""
      ? null
      : requiredString(body.sourcePDFSHA256, "sourcePDFSHA256", 64).toLowerCase();
    if (sourcePDFSHA256 && !isSHA256Hex(sourcePDFSHA256)) throw new Error("sourcePDFSHA256_invalid");

    const signatureImageSHA256 = requiredString(body.signatureImageSHA256, "signatureImageSHA256", 64).toLowerCase();
    if (!isSHA256Hex(signatureImageSHA256)) throw new Error("signatureImageSHA256_invalid");

    const signaturePage = requiredString(body.signaturePage, "signaturePage", 48);
    const signaturePlacement = requiredString(body.signaturePlacement, "signaturePlacement", 48);
    if (!["firstPage", "lastPage", "everyPage"].includes(signaturePage)) throw new Error("signaturePage_invalid");
    if (!["upperLeft", "upperRight", "center", "lowerLeft", "lowerRight"].includes(signaturePlacement)) {
      throw new Error("signaturePlacement_invalid");
    }
    const signedAt = parseDate(body.signedAt, "signedAt");
    const appVersion = requiredString(body.appVersion, "appVersion", 80);
    const pdfExportMode = requiredString(body.pdfExportMode, "pdfExportMode", 80);
    const includeStatementPlaceholder = Boolean(body.includeStatementPlaceholder);
    const issuedAt = new Date().toISOString();
    const keyVersion = configuredKeyVersion();
    const nonce = crypto.randomUUID();

    const manifest: SignatureManifest = {
      appVersion,
      caseID,
      exportID,
      includeStatementPlaceholder,
      issuedAt,
      keyVersion,
      nonce,
      pdfExportMode,
      signatureImageSHA256,
      signaturePage,
      signaturePlacement,
      signedAt,
      sourcePDFSHA256,
      userID: user.id,
    };
    const manifestJSON = canonicalJSONString(manifest);
    const manifestSHA256 = await sha256Hex(manifestJSON);
    const manifestSignature = await signManifest(manifestJSON);
    const encryptedManifest = await encryptManifest(manifestJSON);
    const validationToken = await makeValidationToken(manifestJSON);
    const tokenSHA256 = await sha256Hex(validationToken);

    const admin = serviceClient();
    const { error } = await admin.from("pdf_signature_validations").insert({
      user_id: user.id,
      validation_token: validationToken,
      token_sha256: tokenSHA256,
      status: "issued",
      case_id: caseID,
      source_export_id: exportID,
      source_pdf_sha256: sourcePDFSHA256,
      signature_image_sha256: signatureImageSHA256,
      signature_page: signaturePage,
      signature_placement: signaturePlacement,
      signed_at: signedAt,
      issued_at: issuedAt,
      app_version: appVersion,
      pdf_export_mode: pdfExportMode,
      include_statement_placeholder: includeStatementPlaceholder,
      algorithm: "HMAC-SHA256+A256GCM",
      key_version: keyVersion,
      manifest_sha256: manifestSHA256,
      manifest_signature: manifestSignature,
      encrypted_manifest: encryptedManifest,
    });
    if (error) throw error;

    return jsonResponse({
      validationToken,
      encryptedManifest,
      manifestSignature,
      manifestSHA256,
      algorithm: "HMAC-SHA256+A256GCM",
      keyVersion,
      issuedAt,
      verificationURL: publicVerificationURL(validationToken),
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, { status: 400 });
  }
});
