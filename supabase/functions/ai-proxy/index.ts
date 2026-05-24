import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  buildPrompt,
  enforceFeatureInputLimit,
  estimateCostUSD,
  normalizeFeature,
  safeMetadata,
  sha256Hex,
  systemPrompt,
} from "../_shared/ai.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  let ledgerID: string | null = null;
  let admin: ReturnType<typeof serviceClient> | null = null;

  try {
    const body = await req.json();
    const { user } = await requireUser(req);
    admin = serviceClient();

    if (body.userTriggered !== true) {
      return jsonResponse({ error: "ai_must_be_user_triggered" }, { status: 400 });
    }

    const feature = normalizeFeature(body.feature, body.taskType);
    const rawCompressedTextInput = typeof body.compressedTextInput === "string"
      ? body.compressedTextInput.trim()
      : "";
    if (!rawCompressedTextInput) {
      return jsonResponse({ error: "missing_text_input" }, { status: 400 });
    }

    const caseID = stringOrNull(body.case_id) ?? stringOrNull(body.caseID);
    const idempotencyKey = normalizedIdempotencyKey(body.idempotencyKey) ??
      normalizedIdempotencyKey(body.inputHash) ??
      crypto.randomUUID();
    const wantsStream = body.stream === true ||
      req.headers.get("accept")?.toLowerCase().includes("text/event-stream") === true;

    const { data: pricingRows, error: pricingError } = await admin
      .from("ai_feature_pricing")
      .select("credit_cost, model_tier, max_input_tokens, max_output_tokens, enabled")
      .eq("feature", feature)
      .eq("enabled", true)
      .limit(1);
    if (pricingError) throw pricingError;
    const pricing = pricingRows?.[0];
    if (!pricing) return jsonResponse({ error: "ai_feature_disabled" }, { status: 403 });

    const existingLedger = await findExistingLedger(admin, user.id, idempotencyKey);
    if (existingLedger) {
      const balance = await currentBalance(admin, user.id);
      return duplicateLedgerResponse(existingLedger, balance?.available_credits ?? null);
    }

    const { data: reservationRows, error: reservationError } = await admin.rpc("proofkit_reserve_ai_credits", {
      p_user_id: user.id,
      p_feature: feature,
      p_case_id: caseID,
      p_idempotency_key: idempotencyKey,
    });
    if (reservationError) {
      if (isInsufficientCreditsError(reservationError)) {
        return jsonResponse({ error: "insufficient_ai_credits" }, { status: 402 });
      }

      throw reservationError;
    }

    const reservation = Array.isArray(reservationRows) ? reservationRows[0] : reservationRows;
    ledgerID = reservation?.ledger_id ?? null;
    if (!ledgerID) throw new Error("ai_reservation_missing_ledger_id");

    if (reservation?.was_existing === true) {
      return duplicateLedgerResponse({
        id: ledgerID,
        status: typeof reservation.ledger_status === "string" ? reservation.ledger_status : "pending",
        credits_reserved: numberOrNull(reservation.credits_reserved),
        reservation_expires_at: typeof reservation.expires_at === "string" ? reservation.expires_at : null,
        completed_at: null,
      }, numberOrNull(reservation.remaining_credits));
    }

    const anthropicAPIKey = Deno.env.get("ANTHROPIC_AUTH_TOKEN")?.trim() ??
      Deno.env.get("ANTHROPIC_API_KEY")?.trim();
    if (!anthropicAPIKey) {
      await refund(admin, ledgerID, "anthropic_not_configured");
      return jsonResponse({ error: "anthropic_not_configured" }, { status: 503 });
    }

    const model = Deno.env.get("PROOFKIT_ANTHROPIC_HAIKU_MODEL")?.trim() || "claude-haiku-4-5-20251001";
    const metadata = safeMetadata(body.metadata);
    const inputLimit = enforceFeatureInputLimit(rawCompressedTextInput, pricing.max_input_tokens);
    const userPrompt = buildPrompt(feature, inputLimit.text, metadata);
    const requestHash = await sha256Hex(JSON.stringify({
      feature,
      metadata,
      input: inputLimit.text,
      inputTruncated: inputLimit.truncated,
    }));

    const anthropicMessagesURL = Deno.env.get("PROOFKIT_ANTHROPIC_MESSAGES_URL")?.trim() ||
      `${Deno.env.get("ANTHROPIC_BASE_URL")?.trim() || "https://code.anyxml.com"}/v1/messages`;
    const anthropicRequestBody = {
      model,
      max_tokens: pricing.max_output_tokens,
      temperature: feature === "deep_review" ? 0.15 : 0.2,
      system: systemPrompt(feature),
      messages: [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: userPrompt,
            },
          ],
        },
      ],
    };

    if (wantsStream) {
      return await streamAnthropicResponse({
        admin,
        anthropicAPIKey,
        anthropicMessagesURL,
        body: { ...anthropicRequestBody, stream: true },
        creditsUsed: reservation?.credits_reserved ?? pricing.credit_cost,
        feature,
        inputLimit,
        ledgerID,
        model,
        remainingCredits: numberOrNull(reservation?.remaining_credits),
        requestHash,
        userID: user.id,
      });
    }

    const anthropicResponse = await fetch(anthropicMessagesURL, {
      method: "POST",
      headers: anthropicHeaders(anthropicAPIKey),
      body: JSON.stringify(anthropicRequestBody),
    });

    if (!anthropicResponse.ok) {
      await refund(admin, ledgerID, `anthropic_${anthropicResponse.status}`);
      return jsonResponse({ error: "ai_provider_failed" }, { status: 502 });
    }

    const anthropicJSON = await anthropicResponse.json();
    const outputText = (anthropicJSON.content ?? [])
      .filter((part: { type?: string; text?: string }) => part?.type === "text" && typeof part.text === "string")
      .map((part: { text: string }) => part.text.trim())
      .filter(Boolean)
      .join("\n\n")
      .trim();

    if (!outputText) {
      await refund(admin, ledgerID, "empty_ai_output");
      return jsonResponse({ error: "empty_ai_output" }, { status: 502 });
    }

    const inputTokens = numberOrNull(anthropicJSON.usage?.input_tokens);
    const outputTokens = numberOrNull(anthropicJSON.usage?.output_tokens);
    const cost = estimateCostUSD(inputTokens ?? undefined, outputTokens ?? undefined);
    const responseHash = await sha256Hex(outputText);

    const { error: finalizeError } = await admin.rpc("proofkit_finalize_ai_usage", {
      p_ledger_id: ledgerID,
      p_input_tokens: inputTokens,
      p_output_tokens: outputTokens,
      p_estimated_cost_usd: cost,
      p_actual_cost_usd: null,
      p_request_hash: requestHash,
      p_response_hash: responseHash,
      p_model: model,
    });
    if (finalizeError) throw finalizeError;

    const { data: balanceRows } = await admin.rpc("proofkit_get_ai_credit_balance", {
      p_user_id: user.id,
    });
    const balance = Array.isArray(balanceRows) ? balanceRows[0] : balanceRows;

    return jsonResponse({
      resultID: ledgerID,
      outputText,
      creditsUsed: reservation?.credits_reserved ?? pricing.credit_cost,
      remainingCredits: balance?.available_credits ?? reservation?.remaining_credits ?? null,
      metadata: {
        provider: "anthropic",
        model,
        feature,
        inputTokens: inputTokens == null ? "" : String(inputTokens),
        outputTokens: outputTokens == null ? "" : String(outputTokens),
        inputTruncated: String(inputLimit.truncated),
        inputCharacterLimit: String(inputLimit.maxCharacters),
        inputCharacters: String(inputLimit.usedCharacters),
        originalInputCharacters: inputLimit.truncated ? String(inputLimit.originalCharacters) : "",
      },
    });
  } catch (error) {
    if (error instanceof Response) return error;

    if (ledgerID) {
      try {
        await refund(admin ?? serviceClient(), ledgerID, "edge_function_error");
      } catch (_) {
        // Best effort only. The database ledger keeps the pending reservation
        // visible for operational follow-up if the refund RPC also fails.
      }
    }

    return jsonResponse({ error: (error instanceof Error ? error.message : String(error)) }, { status: 400 });
  }
});

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function stringOrNull(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function isInsufficientCreditsError(error: { message?: string; code?: string; details?: string }): boolean {
  const text = `${error.message ?? ""} ${error.code ?? ""} ${error.details ?? ""}`.toLowerCase();
  return text.includes("insufficient_ai_credits") ||
    text.includes("insufficient ai credits") ||
    text.includes("payment required");
}

function normalizedIdempotencyKey(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, 200);
}

function anthropicHeaders(authToken: string): HeadersInit {
  return {
    "content-type": "application/json",
    "anthropic-version": "2023-06-01",
    "x-api-key": authToken,
    "authorization": `Bearer ${authToken}`,
  };
}

type StreamAnthropicResponseOptions = {
  admin: ReturnType<typeof serviceClient>;
  anthropicAPIKey: string;
  anthropicMessagesURL: string;
  body: Record<string, unknown>;
  creditsUsed: number | null;
  feature: string;
  inputLimit: {
    truncated: boolean;
    maxCharacters: number;
    usedCharacters: number;
    originalCharacters: number;
  };
  ledgerID: string;
  model: string;
  remainingCredits: number | null;
  requestHash: string;
  userID: string;
};

async function streamAnthropicResponse(options: StreamAnthropicResponseOptions): Promise<Response> {
  const {
    admin,
    anthropicAPIKey,
    anthropicMessagesURL,
    body,
    creditsUsed,
    feature,
    inputLimit,
    ledgerID,
    model,
    remainingCredits,
    requestHash,
    userID,
  } = options;

  const anthropicResponse = await fetch(anthropicMessagesURL, {
    method: "POST",
    headers: anthropicHeaders(anthropicAPIKey),
    body: JSON.stringify(body),
  });

  if (!anthropicResponse.ok || !anthropicResponse.body) {
    await refund(admin, ledgerID, `anthropic_${anthropicResponse.status}`);
    return jsonResponse({ error: "ai_provider_failed" }, { status: 502 });
  }

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let outputText = "";
  let inputTokens: number | null = null;
  let outputTokens: number | null = null;

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let isClosed = false;
      const send = (event: string, data: unknown) => {
        controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
      };
      const close = () => {
        if (!isClosed) {
          isClosed = true;
          controller.close();
        }
      };

      try {
        send("start", {
          resultID: ledgerID,
          creditsUsed,
          remainingCredits,
          metadata: {
            provider: "anthropic",
            model,
            feature,
            inputTruncated: String(inputLimit.truncated),
            inputCharacterLimit: String(inputLimit.maxCharacters),
            inputCharacters: String(inputLimit.usedCharacters),
            originalInputCharacters: inputLimit.truncated ? String(inputLimit.originalCharacters) : "",
          },
        });

        let buffer = "";
        for await (const chunk of anthropicResponse.body!) {
          buffer += decoder.decode(chunk, { stream: true });
          const frames = buffer.split("\n\n");
          buffer = frames.pop() ?? "";

          for (const frame of frames) {
            const dataLines = frame
              .split("\n")
              .filter((line) => line.startsWith("data:"))
              .map((line) => line.slice(5).trim())
              .filter((line) => line && line !== "[DONE]");

            for (const line of dataLines) {
              const event = JSON.parse(line);
              if (event.type === "message_start") {
                inputTokens = numberOrNull(event.message?.usage?.input_tokens) ?? inputTokens;
              } else if (event.type === "content_block_delta") {
                const text = typeof event.delta?.text === "string" ? event.delta.text : "";
                if (text) {
                  outputText += text;
                  send("delta", { text });
                }
              } else if (event.type === "message_delta") {
                outputTokens = numberOrNull(event.usage?.output_tokens) ?? outputTokens;
              } else if (event.type === "error") {
                throw new Error("ai_provider_stream_error");
              }
            }
          }
        }

        outputText = outputText.trim();
        if (!outputText) {
          await refund(admin, ledgerID, "empty_ai_output");
          send("error", { error: "empty_ai_output" });
          close();
          return;
        }

        const cost = estimateCostUSD(inputTokens ?? undefined, outputTokens ?? undefined);
        const responseHash = await sha256Hex(outputText);
        const { error: finalizeError } = await admin.rpc("proofkit_finalize_ai_usage", {
          p_ledger_id: ledgerID,
          p_input_tokens: inputTokens,
          p_output_tokens: outputTokens,
          p_estimated_cost_usd: cost,
          p_actual_cost_usd: null,
          p_request_hash: requestHash,
          p_response_hash: responseHash,
          p_model: model,
        });
        if (finalizeError) throw finalizeError;

        const { data: balanceRows } = await admin.rpc("proofkit_get_ai_credit_balance", {
          p_user_id: userID,
        });
        const balance = Array.isArray(balanceRows) ? balanceRows[0] : balanceRows;

        send("done", {
          resultID: ledgerID,
          outputText,
          creditsUsed,
          remainingCredits: balance?.available_credits ?? remainingCredits,
          metadata: {
            provider: "anthropic",
            model,
            feature,
            inputTokens: inputTokens == null ? "" : String(inputTokens),
            outputTokens: outputTokens == null ? "" : String(outputTokens),
            inputTruncated: String(inputLimit.truncated),
            inputCharacterLimit: String(inputLimit.maxCharacters),
            inputCharacters: String(inputLimit.usedCharacters),
            originalInputCharacters: inputLimit.truncated ? String(inputLimit.originalCharacters) : "",
          },
        });
      } catch (error) {
        await refund(admin, ledgerID, "edge_stream_error");
        send("error", { error: error instanceof Error ? error.message : String(error) });
      } finally {
        close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      "connection": "keep-alive",
    },
  });
}

type ExistingLedger = {
  id: string;
  status: string;
  credits_reserved: number | null;
  reservation_expires_at: string | null;
  completed_at: string | null;
};

async function findExistingLedger(
  admin: ReturnType<typeof serviceClient>,
  userID: string,
  idempotencyKey: string,
): Promise<ExistingLedger | null> {
  const { data, error } = await admin
    .from("ai_usage_ledger")
    .select("id,status,credits_reserved,reservation_expires_at,completed_at")
    .eq("user_id", userID)
    .eq("idempotency_key", idempotencyKey)
    .order("created_at", { ascending: false })
    .limit(1);

  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : null;
  if (!row || typeof row.id !== "string" || typeof row.status !== "string") return null;

  return {
    id: row.id,
    status: row.status,
    credits_reserved: numberOrNull(row.credits_reserved),
    reservation_expires_at: typeof row.reservation_expires_at === "string" ? row.reservation_expires_at : null,
    completed_at: typeof row.completed_at === "string" ? row.completed_at : null,
  };
}

async function currentBalance(admin: ReturnType<typeof serviceClient>, userID: string): Promise<{ available_credits?: number } | null> {
  const { data, error } = await admin.rpc("proofkit_get_ai_credit_balance", {
    p_user_id: userID,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] ?? null : data;
}

function duplicateLedgerResponse(ledger: ExistingLedger, remainingCredits: number | null) {
  const error = duplicateErrorCode(ledger.status);
  return jsonResponse({
    error,
    resultID: ledger.id,
    creditsUsed: ledger.credits_reserved ?? 0,
    remainingCredits,
    metadata: {
      duplicateIdempotencyKey: "true",
      ledgerStatus: ledger.status,
      reservationExpiresAt: ledger.reservation_expires_at ?? "",
      completedAt: ledger.completed_at ?? "",
    },
  }, { status: 409 });
}

function duplicateErrorCode(status: string): string {
  switch (status) {
    case "succeeded":
      return "duplicate_already_completed";
    case "pending":
      return "request_already_pending";
    case "failed":
    case "refunded":
    case "cancelled":
      return "idempotency_key_already_finalized_use_new_key";
    default:
      return "duplicate_idempotency_key";
  }
}

async function refund(admin: ReturnType<typeof serviceClient>, ledgerID: string, errorCode: string) {
  await admin.rpc("proofkit_refund_ai_reservation", {
    p_ledger_id: ledgerID,
    p_error_code: errorCode,
  });
}
