import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Connection": "keep-alive",
};

type StartPayload = {
  redirect_uri?: string;
};

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const clientId = Deno.env.get("GOOGLE_OAUTH_CLIENT_ID");
  if (!clientId) {
    return jsonResponse({ error: "missing_google_oauth_client_id" }, 500);
  }

  let payload: StartPayload;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (!payload.redirect_uri) {
    return jsonResponse({ error: "missing_redirect_uri" }, 400);
  }

  const scopes = Deno.env.get("GMAIL_OAUTH_SCOPES") ?? "https://www.googleapis.com/auth/gmail.readonly";
  const state = crypto.randomUUID();
  const codeVerifier = base64URL(crypto.getRandomValues(new Uint8Array(64)));
  const codeChallenge = await sha256Base64URL(codeVerifier);
  const authorizationURL = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authorizationURL.searchParams.set("client_id", clientId);
  authorizationURL.searchParams.set("redirect_uri", payload.redirect_uri);
  authorizationURL.searchParams.set("response_type", "code");
  authorizationURL.searchParams.set("scope", scopes);
  authorizationURL.searchParams.set("code_challenge", codeChallenge);
  authorizationURL.searchParams.set("code_challenge_method", "S256");
  authorizationURL.searchParams.set("access_type", "offline");
  authorizationURL.searchParams.set("prompt", "consent");
  authorizationURL.searchParams.set("include_granted_scopes", "true");
  authorizationURL.searchParams.set("state", state);

  return jsonResponse({
    authorization_url: authorizationURL.toString(),
    state,
    code_verifier: codeVerifier,
  });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

async function sha256Base64URL(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return base64URL(new Uint8Array(digest));
}

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}
