import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  if (req.method !== "POST") {
    return jsonResponse(
      { error: "method_not_allowed" },
      { status: 405, headers: { Allow: "POST, OPTIONS" } },
    );
  }

  try {
    const { user } = await requireUser(req);
    const admin = serviceClient();
    const jwt = bearerToken(req);

    if (jwt) {
      const { error: signOutError } = await admin.auth.admin.signOut(jwt, "global");
      if (signOutError) {
        console.warn("delete-account session revoke failed", signOutError.message);
      }
    }

    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;

    return jsonResponse({ deleted: true });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: (error instanceof Error ? error.message : String(error)) }, { status: 400 });
  }
});

function bearerToken(req: Request): string | null {
  const authorization = req.headers.get("Authorization")?.trim() ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}
