import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Connection": "keep-alive",
};

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return jsonResponse({ error: "missing_authorization" }, 401);
  }

  const supabaseURL = requireEnv("SUPABASE_URL");
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseURL, serviceRoleKey, {
    global: { headers: { Authorization: authorization } },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "invalid_user_session" }, 401);
  }

  const { error: tokenDeleteError } = await supabase
    .schema("private")
    .from("gmail_oauth_tokens")
    .delete()
    .eq("user_id", userData.user.id);
  if (tokenDeleteError) {
    return jsonResponse({ error: "token_delete_failed" }, 500);
  }

  const { error: connectionError } = await supabase
    .from("source_connections")
    .upsert({
      user_id: userData.user.id,
      kind: "gmail",
      status: "revoked",
      provider_account_label: null,
      provider_subject: null,
      oauth_scopes: [],
      provider_metadata: {},
      last_synced_at: null,
      error_code: null,
    }, { onConflict: "user_id,kind" });
  if (connectionError) {
    return jsonResponse({ error: "connection_revoke_failed" }, 500);
  }

  return jsonResponse({
    status: "revoked",
    provider_account_label: null,
    last_synced_at: null,
    error_code: null,
  });
});

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing ${name}`);
  }

  return value;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}
