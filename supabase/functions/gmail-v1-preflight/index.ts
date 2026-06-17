import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Connection": "keep-alive",
};

const requiredSecrets = [
  "GOOGLE_OAUTH_CLIENT_ID",
  "GMAIL_TOKEN_ENCRYPTION_KEY",
];

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const missing = requiredSecrets.filter((name) => !Deno.env.get(name));

  return jsonResponse({
    is_configured: missing.length === 0,
    missing,
  });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}
