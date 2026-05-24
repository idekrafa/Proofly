import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { user } = await requireUser(req);
    const admin = serviceClient();
    const { data, error } = await admin.rpc("proofkit_get_ai_credit_balance", {
      p_user_id: user.id,
    });
    if (error) throw error;

    const row = Array.isArray(data) ? data[0] : data;
    return jsonResponse({
      availableCredits: row?.available_credits ?? 0,
      reservedCredits: row?.reserved_credits ?? 0,
      includedMonthlyCredits: row?.included_monthly_credits ?? 0,
      renewsAt: row?.renews_at ?? null,
      updatedAt: row?.updated_at ?? null,
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: (error instanceof Error ? error.message : String(error)) }, { status: 400 });
  }
});
