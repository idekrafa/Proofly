import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { isSHA256Hex, optionalUUID, requiredString } from "../_shared/signature.ts";
import {
  base64ToBytes,
  DEFAULT_EXPIRY_DAYS,
  makeRequestToken,
  MAX_EXPIRY_DAYS,
  MAX_PDF_BYTES,
  sha256HexOfBytes,
  SIGNATURE_REQUEST_BUCKET,
  signRequestPageURL,
  tokenLookupHash,
} from "../_shared/signatureRequest.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { user } = await requireUser(req);
    const body = await req.json();

    const caseID = optionalUUID(body.caseID, "caseID");
    if (!caseID) throw new Error("caseID_required");
    const exportID = optionalUUID(body.exportID, "exportID");
    const documentTitle = requiredString(body.documentTitle, "documentTitle", 200);
    const requesterName = body.requesterName == null || body.requesterName === ""
      ? null
      : requiredString(body.requesterName, "requesterName", 120);
    const message = body.message == null || body.message === ""
      ? null
      : requiredString(body.message, "message", 500);
    const appVersion = requiredString(body.appVersion, "appVersion", 80);

    const signaturePage = requiredString(body.signaturePage, "signaturePage", 48);
    const signaturePlacement = requiredString(body.signaturePlacement, "signaturePlacement", 48);
    if (!["firstPage", "lastPage", "everyPage"].includes(signaturePage)) throw new Error("signaturePage_invalid");
    if (!["upperLeft", "upperRight", "center", "lowerLeft", "lowerRight"].includes(signaturePlacement)) {
      throw new Error("signaturePlacement_invalid");
    }

    const expiresInDaysRaw = Number(body.expiresInDays ?? DEFAULT_EXPIRY_DAYS);
    const expiresInDays = Number.isFinite(expiresInDaysRaw)
      ? Math.min(Math.max(Math.round(expiresInDaysRaw), 1), MAX_EXPIRY_DAYS)
      : DEFAULT_EXPIRY_DAYS;

    const pdfSHA256 = requiredString(body.pdfSHA256, "pdfSHA256", 64).toLowerCase();
    if (!isSHA256Hex(pdfSHA256)) throw new Error("pdfSHA256_invalid");
    const pdfBase64 = requiredString(body.pdfBase64, "pdfBase64", 32 * 1024 * 1024);
    const pdfBytes = base64ToBytes(pdfBase64);
    if (pdfBytes.byteLength === 0) throw new Error("pdf_empty");
    if (pdfBytes.byteLength > MAX_PDF_BYTES) throw new Error("pdf_too_large");
    const computedPDFSHA256 = await sha256HexOfBytes(pdfBytes);
    if (computedPDFSHA256 !== pdfSHA256) throw new Error("pdfSHA256_mismatch");

    const requestToken = makeRequestToken();
    const requestTokenSHA256 = await tokenLookupHash(requestToken);
    const requestID = crypto.randomUUID();
    const pdfStoragePath = `${user.id}/${requestID}/document.pdf`;
    const expiresAt = new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000).toISOString();

    const admin = serviceClient();
    const upload = await admin.storage.from(SIGNATURE_REQUEST_BUCKET).upload(pdfStoragePath, pdfBytes, {
      contentType: "application/pdf",
      upsert: true,
    });
    if (upload.error) throw upload.error;

    // One active request per case: superseded pending requests are cancelled so
    // old links stop working when a new one is created.
    const { error: supersedeError } = await admin
      .from("pdf_signature_requests")
      .update({ status: "cancelled", cancelled_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq("user_id", user.id)
      .eq("case_id", caseID)
      .eq("status", "pending");
    if (supersedeError) throw supersedeError;

    const { error } = await admin.from("pdf_signature_requests").insert({
      id: requestID,
      user_id: user.id,
      case_id: caseID,
      source_export_id: exportID,
      request_token: requestToken,
      request_token_sha256: requestTokenSHA256,
      status: "pending",
      document_title: documentTitle,
      requester_name: requesterName,
      message,
      signature_page: signaturePage,
      signature_placement: signaturePlacement,
      pdf_storage_path: pdfStoragePath,
      pdf_sha256: pdfSHA256,
      expires_at: expiresAt,
      app_version: appVersion,
    });
    if (error) throw error;

    return jsonResponse({
      requestID,
      status: "pending",
      shareURL: signRequestPageURL(requestToken),
      expiresAt,
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, { status: 400 });
  }
});
