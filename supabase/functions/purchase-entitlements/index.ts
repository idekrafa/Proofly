import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { user } = await requireUser(req);
    const admin = serviceClient();
    const { data, error } = await admin
      .from("subscription_accounts")
      .select("id, plan, status, entitlement_id, provider, current_period_end, updated_at")
      .eq("user_id", user.id)
      .order("updated_at", { ascending: false });
    if (error) throw error;

    const rows = (data ?? []).map((row) => ({
      id: row.id,
      productID: row.plan,
      entitlement: row.entitlement_id ?? "pro",
      isActive: ["trialing", "active_weekly", "active_monthly"].includes(row.status),
      source: row.provider ?? "revenuecat",
      expiresAt: row.current_period_end ?? null,
      updatedAt: row.updated_at ?? null,
    }));

    return jsonResponse(rows);
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: (error instanceof Error ? error.message : String(error)) }, { status: 400 });
  }
});
