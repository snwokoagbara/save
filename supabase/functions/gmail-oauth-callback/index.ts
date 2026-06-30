import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Connection": "keep-alive",
};

type CallbackPayload = {
  code?: string;
  state?: string;
  code_verifier?: string;
  redirect_uri?: string;
};

type GoogleTokenResponse = {
  access_token?: string;
  expires_in?: number;
  refresh_token?: string;
  scope?: string;
  token_type?: string;
  error?: string;
  error_description?: string;
};

type GmailProfileResponse = {
  emailAddress?: string;
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
  const googleClientID = requireEnv("GOOGLE_OAUTH_CLIENT_ID");
  const tokenEncryptionKey = requireEnv("GMAIL_TOKEN_ENCRYPTION_KEY");

  let payload: CallbackPayload;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (!payload.code || !payload.state || !payload.code_verifier || !payload.redirect_uri) {
    return jsonResponse({ error: "missing_oauth_callback_fields" }, 400);
  }

  const userClient = createClient(supabaseURL, serviceRoleKey, {
    global: { headers: { Authorization: authorization } },
  });
  const serviceClient = createClient(supabaseURL, serviceRoleKey);
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "invalid_user_session" }, 401);
  }

  const tokenResponse = await exchangeCode({
    code: payload.code,
    codeVerifier: payload.code_verifier,
    redirectURI: payload.redirect_uri,
    clientID: googleClientID,
    clientSecret: Deno.env.get("GOOGLE_OAUTH_CLIENT_SECRET") ?? undefined,
  });
  if (!tokenResponse.access_token) {
    return jsonResponse({
      error: tokenResponse.error ?? "google_token_exchange_failed",
      error_description: tokenResponse.error_description,
    }, 502);
  }

  const profile = await loadGmailProfile(tokenResponse.access_token);
  const accountLabel = profile.emailAddress ?? "Gmail";
  const scopes = (tokenResponse.scope ?? "").split(" ").filter(Boolean);
  const expiresAt = tokenResponse.expires_in
    ? new Date(Date.now() + tokenResponse.expires_in * 1000).toISOString()
    : null;

  if (tokenResponse.refresh_token) {
    const encryptedRefreshToken = await encryptText(tokenResponse.refresh_token, tokenEncryptionKey);
    const { error: tokenStoreError } = await serviceClient.rpc("upsert_gmail_oauth_token", {
      p_user_id: userData.user.id,
      p_provider_subject: profile.emailAddress ?? null,
      p_encrypted_refresh_token: encryptedRefreshToken,
      p_access_token_expires_at: expiresAt,
      p_scope: scopes,
    });
    if (tokenStoreError) {
      console.error("token_store_failed", tokenStoreError);
      return jsonResponse({ error: "token_store_failed", error_description: tokenStoreError.message }, 500);
    }
  }

  const { error: connectionError } = await serviceClient
    .from("source_connections")
    .upsert({
      user_id: userData.user.id,
      kind: "gmail",
      status: "connected",
      provider_account_label: accountLabel,
      provider_subject: profile.emailAddress ?? null,
      oauth_scopes: scopes,
      provider_metadata: {
        token_type: tokenResponse.token_type ?? null,
        has_refresh_token: Boolean(tokenResponse.refresh_token),
      },
      last_synced_at: null,
      error_code: null,
    }, { onConflict: "user_id,kind" });
  if (connectionError) {
    console.error("connection_upsert_failed", connectionError);
    return jsonResponse({ error: "connection_upsert_failed", error_description: connectionError.message }, 500);
  }

  return jsonResponse({
    status: "connected",
    provider_account_label: accountLabel,
    last_synced_at: null,
    error_code: null,
  });
});

async function exchangeCode(input: {
  code: string;
  codeVerifier: string;
  redirectURI: string;
  clientID: string;
  clientSecret?: string;
}): Promise<GoogleTokenResponse> {
  const body = new URLSearchParams();
  body.set("code", input.code);
  body.set("client_id", input.clientID);
  body.set("code_verifier", input.codeVerifier);
  body.set("redirect_uri", input.redirectURI);
  body.set("grant_type", "authorization_code");
  if (input.clientSecret) {
    body.set("client_secret", input.clientSecret);
  }

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  return await response.json();
}

async function loadGmailProfile(accessToken: string): Promise<GmailProfileResponse> {
  const response = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/profile", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) {
    return {};
  }

  return await response.json();
}

async function encryptText(plaintext: string, keyMaterial: string): Promise<string> {
  const keyDigest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(keyMaterial));
  const key = await crypto.subtle.importKey("raw", keyDigest, "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(plaintext),
  );

  return `${base64URL(iv)}.${base64URL(new Uint8Array(ciphertext))}`;
}

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
