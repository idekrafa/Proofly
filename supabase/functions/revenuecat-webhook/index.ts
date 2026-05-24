import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";

type RevenueCatEvent = {
  id?: string;
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  product_id?: string;
  entitlement_id?: string;
  entitlement_ids?: string[];
  purchased_at_ms?: number;
  expiration_at_ms?: number;
  grace_period_expiration_at_ms?: number;
  period_type?: string;
  cancel_reason?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  try {
    verifyWebhookAuthorization(req);

    const payload = await req.json();
    const event: RevenueCatEvent = payload.event ?? payload;
    if ((event.type ?? "").toUpperCase() === "TEST") {
      return jsonResponse({ ok: true, test: true });
    }

    const userID = revenueCatUserID(event);
    if (!userID) return jsonResponse({ error: "missing_app_user_id" }, { status: 400 });

    const productID = event.product_id ?? "";
    const plan = planFromEvent(event, productID);
    const status = statusFromEvent(event, plan);
    const periodStart = dateFromMillis(event.purchased_at_ms) ?? new Date();
    const periodEnd = dateFromMillis(event.expiration_at_ms) ?? fallbackPeriodEnd(plan, periodStart);
    const trialEndsAt = status === "trialing" ? periodEnd : null;
    const renewsIntoPlan = status === "trialing" ? renewingPlanForTrial(productID) : null;
    const entitlementID = event.entitlement_id ?? event.entitlement_ids?.[0] ?? "pro";

    const admin = serviceClient();
    const { error } = await admin.rpc("proofkit_sync_subscription_account", {
      p_user_id: userID,
      p_provider_customer_id: event.original_app_user_id ?? event.app_user_id ?? userID,
      p_entitlement_id: entitlementID,
      p_plan: plan,
      p_status: status,
      p_current_period_start: periodStart.toISOString(),
      p_current_period_end: periodEnd.toISOString(),
      p_trial_ends_at: trialEndsAt?.toISOString() ?? null,
      p_renews_into_plan: renewsIntoPlan,
      p_source_event_id: event.id ?? null,
    });
    if (error) throw error;

    return jsonResponse({ ok: true });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, { status: 400 });
  }
});

function verifyWebhookAuthorization(req: Request) {
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_AUTHORIZATION")?.trim();
  if (!expected) return;

  const actual = req.headers.get("Authorization")?.trim() ?? "";
  if (actual !== expected && actual !== `Bearer ${expected}`) {
    throw new Error("invalid_webhook_authorization");
  }
}

function revenueCatUserID(event: RevenueCatEvent): string | null {
  const candidates = [event.app_user_id, event.original_app_user_id, ...(event.aliases ?? [])]
    .filter((value): value is string => typeof value === "string" && value.trim().length > 0);

  return candidates.find(isUUID) ?? null;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value.trim());
}

function planFromEvent(event: RevenueCatEvent, productID: string): "trial_weekly_intro" | "weekly_pro" | "monthly_pro" | "none" {
  const product = productID.toLowerCase();
  if ((event.period_type ?? "").toLowerCase() === "trial") return "trial_weekly_intro";
  if (product.includes("monthly") || product.includes("month")) return "monthly_pro";
  if (product.includes("weekly") || product.includes("week")) return "weekly_pro";
  return "none";
}

function statusFromEvent(
  event: RevenueCatEvent,
  plan: "trial_weekly_intro" | "weekly_pro" | "monthly_pro" | "none",
): "trialing" | "active_weekly" | "active_monthly" | "expired" | "cancelled" | "billing_retry" | "revoked_or_refunded" {
  const type = (event.type ?? "").toUpperCase();
  const periodType = (event.period_type ?? "").toLowerCase();
  const cancelReason = (event.cancel_reason ?? "").toUpperCase();

  if (type.includes("REFUND") || cancelReason.includes("REFUND")) return "revoked_or_refunded";
  if (type.includes("EXPIRATION")) return "expired";
  if (type.includes("CANCELLATION")) {
    if (cancelReason === "CUSTOMER_SUPPORT" || cancelReason === "DEVELOPER_INITIATED") {
      return "revoked_or_refunded";
    }

    return activeStatusForPlan(plan) ?? "cancelled";
  }

  if (type.includes("BILLING")) {
    const now = Date.now();
    const graceEndsAt = millisValue(event.grace_period_expiration_at_ms);
    const expiresAt = millisValue(event.expiration_at_ms);
    if ((graceEndsAt !== null && graceEndsAt > now) || (expiresAt !== null && expiresAt > now)) {
      return activeStatusForPlan(plan) ?? "billing_retry";
    }

    return "billing_retry";
  }

  if (type === "TEMPORARY_ENTITLEMENT_GRANT") return activeStatusForPlan(plan) ?? "billing_retry";
  if (periodType === "trial" || plan === "trial_weekly_intro") return "trialing";
  return activeStatusForPlan(plan) ?? "expired";
}

function dateFromMillis(value: unknown): Date | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return new Date(value);
}

function millisValue(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value;
}

function activeStatusForPlan(
  plan: "trial_weekly_intro" | "weekly_pro" | "monthly_pro" | "none",
): "trialing" | "active_weekly" | "active_monthly" | null {
  if (plan === "trial_weekly_intro") return "trialing";
  if (plan === "weekly_pro") return "active_weekly";
  if (plan === "monthly_pro") return "active_monthly";
  return null;
}

function renewingPlanForTrial(productID: string): "weekly_pro" | "monthly_pro" {
  const product = productID.toLowerCase();
  if (product.includes("monthly") || product.includes("month")) return "monthly_pro";
  return "weekly_pro";
}

function fallbackPeriodEnd(plan: string, start: Date): Date {
  const end = new Date(start);
  if (plan === "monthly_pro") {
    end.setMonth(end.getMonth() + 1);
  } else if (plan === "weekly_pro" || plan === "trial_weekly_intro") {
    end.setDate(end.getDate() + 7);
  } else {
    end.setSeconds(end.getSeconds() + 1);
  }
  return end;
}
