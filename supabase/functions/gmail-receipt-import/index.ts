import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Connection": "keep-alive",
};

type TokenRow = {
  encrypted_refresh_token: string;
};

type GoogleTokenResponse = {
  access_token?: string;
  expires_in?: number;
  error?: string;
};

type GmailListResponse = {
  messages?: { id: string; threadId?: string }[];
};

type GmailMessage = {
  id: string;
  threadId?: string;
  snippet?: string;
  internalDate?: string;
  payload?: {
    headers?: { name: string; value: string }[];
  };
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
  const userClient = createClient(supabaseURL, serviceRoleKey, {
    global: { headers: { Authorization: authorization } },
  });
  const serviceClient = createClient(supabaseURL, serviceRoleKey);

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "invalid_user_session" }, 401);
  }

  const { data: tokenRows, error: tokenError } = await serviceClient
    .rpc("gmail_oauth_token_for", { p_user_id: userData.user.id });
  const tokenRow = firstTokenRow(tokenRows);
  if (tokenError || !tokenRow) {
    return jsonResponse({ error: "gmail_not_connected" }, 409);
  }

  const refreshToken = await decryptText(tokenRow.encrypted_refresh_token, tokenEncryptionKey);
  const tokenResponse = await refreshAccessToken({
    refreshToken,
    clientID: googleClientID,
    clientSecret: Deno.env.get("GOOGLE_OAUTH_CLIENT_SECRET") ?? undefined,
  });
  if (!tokenResponse.access_token) {
    await markConnectionFailed(serviceClient, userData.user.id, tokenResponse.error ?? "gmail_refresh_failed");
    return jsonResponse({ error: tokenResponse.error ?? "gmail_refresh_failed" }, 502);
  }

  const query = Deno.env.get("GMAIL_RECEIPT_QUERY")
    ?? '(receipt OR invoice OR pharmacy OR dental OR vision OR HSA OR FSA OR HealthEquity OR WEX OR Inspira OR CVS OR Walgreens) newer_than:2y';
  const maxResults = Number(Deno.env.get("GMAIL_IMPORT_MAX_RESULTS") ?? "10");
  const messages = await listMessages(tokenResponse.access_token, query, maxResults);
  let importedReceiptCount = 0;
  let importedLineItemCount = 0;

  for (const messageRef of messages.messages ?? []) {
    const alreadyImported = await hasImportedMessage(serviceClient, userData.user.id, messageRef.id);
    if (alreadyImported) {
      continue;
    }

    const message = await getMessage(tokenResponse.access_token, messageRef.id);
    const amount = parseAmount(message.snippet ?? "");
    if (amount === null) {
      continue;
    }

    const receiptID = crypto.randomUUID();
    const merchant = merchantName(message) ?? "Gmail receipt";
    const purchasedAt = purchasedDate(message);
    const { error: receiptError } = await serviceClient
      .from("receipts")
      .insert({
        id: receiptID,
        user_id: userData.user.id,
        source: "gmail",
        status: "needs_review",
        merchant,
        purchased_at: purchasedAt,
        total_amount: amount,
        raw_ocr_text: message.snippet ?? "",
        source_metadata: {
          gmail_message_id: message.id,
          gmail_thread_id: message.threadId ?? null,
          subject: headerValue(message, "Subject"),
        },
      });
    if (receiptError) {
      continue;
    }

    const { error: lineItemError } = await serviceClient
      .from("receipt_line_items")
      .insert({
        user_id: userData.user.id,
        receipt_id: receiptID,
        original_text: message.snippet ?? "",
        normalized_name: "Email receipt review",
        amount,
        eligibility: "needs_review",
        confidence: 0.35,
        evidence_labels: ["gmail"],
      });
    if (!lineItemError) {
      importedLineItemCount += 1;
    }

    await serviceClient.rpc("insert_gmail_imported_message", {
      p_user_id: userData.user.id,
      p_gmail_message_id: message.id,
      p_receipt_id: receiptID,
    });
    importedReceiptCount += 1;
  }

  await serviceClient
    .from("source_connections")
    .upsert({
      user_id: userData.user.id,
      kind: "gmail",
      status: "connected",
      last_synced_at: new Date().toISOString(),
      error_code: null,
    }, { onConflict: "user_id,kind" });

  return jsonResponse({
    imported_receipt_count: importedReceiptCount,
    imported_line_item_count: importedLineItemCount,
  });
});

async function refreshAccessToken(input: {
  refreshToken: string;
  clientID: string;
  clientSecret?: string;
}): Promise<GoogleTokenResponse> {
  const body = new URLSearchParams();
  body.set("refresh_token", input.refreshToken);
  body.set("client_id", input.clientID);
  body.set("grant_type", "refresh_token");
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

async function listMessages(accessToken: string, query: string, maxResults: number): Promise<GmailListResponse> {
  const url = new URL("https://gmail.googleapis.com/gmail/v1/users/me/messages");
  url.searchParams.set("q", query);
  url.searchParams.set("maxResults", String(maxResults));

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) {
    return {};
  }

  return await response.json();
}

async function getMessage(accessToken: string, messageID: string): Promise<GmailMessage> {
  const url = new URL(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageID}`);
  url.searchParams.set("format", "metadata");
  url.searchParams.append("metadataHeaders", "From");
  url.searchParams.append("metadataHeaders", "Subject");
  url.searchParams.append("metadataHeaders", "Date");

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  return await response.json();
}

async function hasImportedMessage(supabase: ReturnType<typeof createClient>, userID: string, messageID: string): Promise<boolean> {
  const { data } = await supabase.rpc("has_gmail_imported_message", {
    p_user_id: userID,
    p_gmail_message_id: messageID,
  });

  return Boolean(data);
}

function firstTokenRow(data: unknown): TokenRow | null {
  if (Array.isArray(data)) {
    return data[0] as TokenRow | undefined ?? null;
  }

  return data as TokenRow | null;
}

async function markConnectionFailed(supabase: ReturnType<typeof createClient>, userID: string, errorCode: string): Promise<void> {
  await supabase
    .from("source_connections")
    .upsert({
      user_id: userID,
      kind: "gmail",
      status: "failed",
      error_code: errorCode,
    }, { onConflict: "user_id,kind" });
}

function parseAmount(snippet: string): number | null {
  const matches = [...snippet.matchAll(/\$([0-9]+(?:\.[0-9]{2})?)/g)]
    .map((match) => Number(match[1]))
    .filter((amount) => Number.isFinite(amount) && amount > 0);
  if (matches.length === 0) {
    return null;
  }

  return Math.max(...matches);
}

function merchantName(message: GmailMessage): string | null {
  const from = headerValue(message, "From");
  if (!from) {
    return headerValue(message, "Subject");
  }

  return from.replace(/<[^>]+>/g, "").replaceAll('"', "").trim() || null;
}

function purchasedDate(message: GmailMessage): string | null {
  if (!message.internalDate) {
    return null;
  }

  const date = new Date(Number(message.internalDate));
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString().slice(0, 10);
}

function headerValue(message: GmailMessage, name: string): string | null {
  const header = message.payload?.headers?.find((candidate) => candidate.name.toLowerCase() === name.toLowerCase());
  return header?.value ?? null;
}

async function decryptText(encryptedValue: string, keyMaterial: string): Promise<string> {
  const [ivText, ciphertextText] = encryptedValue.split(".");
  if (!ivText || !ciphertextText) {
    throw new Error("Invalid encrypted token");
  }

  const keyDigest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(keyMaterial));
  const key = await crypto.subtle.importKey("raw", keyDigest, "AES-GCM", false, ["decrypt"]);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64URLToBytes(ivText) },
    key,
    base64URLToBytes(ciphertextText),
  );

  return new TextDecoder().decode(plaintext);
}

function base64URLToBytes(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
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
