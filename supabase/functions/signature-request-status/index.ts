import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { optionalUUID } from "../_shared/signature.ts";
import {
  bytesToBase64,
  isExpired,
  SIGNATURE_REQUEST_BUCKET,
  type SignatureRequestRow,
  signRequestPageURL,
} from "../_shared/signatureRequest.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { user } = await requireUser(req);
    const body = await req.json();

    const requestID = optionalUUID(body.requestID, "requestID");
    const caseID = optionalUUID(body.caseID, "caseID");
    if (!requestID && !caseID) throw new Error("requestID_or_caseID_required");
    const cancel = body.cancel === true;
    const includeSignatureImage = body.includeSignatureImage !== false;

    const admin = serviceClient();
    let query = admin
      .from("pdf_signature_requests")
      .select("*")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(1);
    query = requestID ? query.eq("id", requestID) : query.eq("case_id", caseID!);

    const { data, error } = await query.maybeSingle();
    if (error) throw error;
    const row = data as SignatureRequestRow | null;
    if (!row) return jsonResponse({ status: "none" });

    if (row.status === "pending" && isExpired(row)) {
      row.status = "expired";
      await admin
        .from("pdf_signature_requests")
        .update({ status: "expired", updated_at: new Date().toISOString() })
        .eq("id", row.id)
        .eq("status", "pending");
    }

    if (cancel && row.status === "pending") {
      const now = new Date().toISOString();
      const { error: cancelError } = await admin
        .from("pdf_signature_requests")
        .update({ status: "cancelled", cancelled_at: now, updated_at: now })
        .eq("id", row.id)
        .eq("status", "pending");
      if (cancelError) throw cancelError;
      row.status = "cancelled";
    }

    let signatureImageBase64: string | null = null;
    if (includeSignatureImage && row.status === "signed" && row.signature_image_path) {
      const download = await admin.storage.from(SIGNATURE_REQUEST_BUCKET).download(row.signature_image_path);
      if (!download.error && download.data) {
        signatureImageBase64 = bytesToBase64(new Uint8Array(await download.data.arrayBuffer()));
      }
    }

    return jsonResponse({
      requestID: row.id,
      status: row.status,
      caseID: row.case_id,
      exportID: row.source_export_id,
      documentTitle: row.document_title,
      shareURL: row.status === "pending" ? signRequestPageURL(row.request_token) : null,
      expiresAt: row.expires_at,
      createdAt: row.created_at,
      signaturePage: row.signature_page,
      signaturePlacement: row.signature_placement,
      pdfSHA256: row.pdf_sha256,
      signerName: row.signer_name,
      signedAt: row.signed_at,
      signatureImageSHA256: row.signature_image_sha256,
      signatureImageBase64,
      signaturePositionPage: row.signature_position_page,
      signaturePositionX: row.signature_position_x,
      signaturePositionY: row.signature_position_y,
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, { status: 400 });
  }
});
