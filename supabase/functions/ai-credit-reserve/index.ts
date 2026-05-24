import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { normalizeFeature } from "../_shared/ai.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  try {
    const body = await req.json();
    const { user } = await requireUser(req);
    const admin = serviceClient();
    const feature = normalizeFeature(body.feature, body.taskType);
    const caseID = typeof body.caseID === "string" ? body.caseID : null;
    const idempotencyKey = typeof body.idempotencyKey === "string" ? body.idempotencyKey : crypto.randomUUID();

    const { data, error } = await admin.rpc("proofkit_reserve_ai_credits", {
      p_user_id: user.id,
      p_feature: feature,
      p_case_id: caseID,
      p_idempotency_key: idempotencyKey,
    });
    if (error) throw error;

    const row = Array.isArray(data) ? data[0] : data;
    return jsonResponse({
      reservationID: row?.ledger_id,
      creditsReserved: row?.credits_reserved ?? 0,
      remainingCredits: row?.remaining_credits ?? 0,
      expiresAt: row?.expires_at ?? null,
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: (error instanceof Error ? error.message : String(error)) }, { status: 400 });
  }
});
