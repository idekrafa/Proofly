import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "../..");
const fixtures = JSON.parse(
  await readFile(path.join(__dirname, "fixtures", "synthetic-cases.json"), "utf8"),
);

const runID = process.env.PROOFKIT_E2E_RUN_ID ?? `proofly-e2e-${Date.now()}-${randomUUID().slice(0, 8)}`;
const requiredSupabaseEnv = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"];
const hasSupabaseEnv = requiredSupabaseEnv.every((name) => Boolean(process.env[name]?.trim()));
const liveAIEnabled = process.env.LIVE_AI_E2E === "true";
const spawnFunctions = process.env.PROOFKIT_E2E_SPAWN_FUNCTIONS === "true";
const confirmedMockEdge = process.env.PROOFKIT_E2E_CONFIRM_MOCK_EDGE === "true";
const edgeEnabled = liveAIEnabled || spawnFunctions || confirmedMockEdge;
let report;

after(async () => {
  await report.write(path.join(repoRoot, "test-results"));
});

test("static app and Edge Function guardrails", async (t) => {
  await t.test("PostHog is not a test dependency", async () => {
    const source = await readFile(fileURLToPath(import.meta.url), "utf8");
    const analyticsHost = ["posthog", "com"].join(".");
    assert.equal(source.includes(`fetch("${analyticsHost}`), false);
    assert.equal(source.includes(`fetch('${analyticsHost}`), false);
    assert.equal(source.includes("PostHog"), true, "This test may mention the product name but must not call it.");
  });

  await t.test("paywall and confirmation copy include current credit rules", async () => {
    const paywall = await readFile(path.join(repoRoot, "ProofKit/Views/PaywallView.swift"), "utf8");
    const timeline = await readFile(path.join(repoRoot, "ProofKit/Views/TimelineView.swift"), "utf8");
    const aiService = await readFile(path.join(repoRoot, "ProofKit/AI/AIService.swift"), "utf8");

    assert.match(paywall, /Start your free trial/);
    assert.match(paywall, /Full Pro access during trial/);
    assert.match(paywall, /3 AI credits/);
    assert.match(paywall, /\$3\.99\/week after trial|after trial/);
    assert.match(paywall, /15 AI credits\/week/);
    assert.match(paywall, /75 AI credits\/month/);
    assert.match(timeline, /Use AI credits\?/);
    assert.match(timeline, /Use \\?\(quote\.creditCost\\?\) AI credits/);
    assert.match(aiService, /but you have \\?\(balance\.availableCredits\\?\) available/);
  });

  await t.test("local AI output remains separate from original proof fields", async () => {
    const router = await readFile(path.join(repoRoot, "ProofKit/AI/AITaskRouter.swift"), "utf8");
    const cacheModel = await readFile(path.join(repoRoot, "ProofKit/Models/AIResultCache.swift"), "utf8");
    const evidenceEditor = await readFile(path.join(repoRoot, "ProofKit/Views/EvidenceDetailEditView.swift"), "utf8");

    assert.match(cacheModel, /final class AIResultCache/);
    assert.match(cacheModel, /resultJSON/);
    assert.match(cacheModel, /must not replace original user\/OCR\/file fields/);
    assert.match(router, /modelContext\.insert\(cache\)/);
    assert.match(router, /try modelContext\.save\(\)/);
    assert.equal(/\.userNotes\s*=\s*rewrittenNote/.test(evidenceEditor), false);
    assert.equal(/\.originalOCRText\s*=/.test(router), false);
    assert.equal(/caseFile\.userNotes\s*=/.test(router), false);
    assert.match(evidenceEditor, /userCleanedNote\s*=\s*rewrittenNote/);
  });

  await t.test("offline queue behavior has source-level coverage", async () => {
    const queue = await readFile(path.join(repoRoot, "ProofKit/Services/AIRequestQueueService.swift"), "utf8");
    const queueModel = await readFile(path.join(repoRoot, "ProofKit/Models/AIRequestQueueItem.swift"), "utf8");

    assert.match(queueModel, /case waitingForCredits/);
    assert.match(queue, /markQueueWaitingForCredits/);
    assert.match(queue, /while let item = nextQueuedItem/);
    assert.match(queue, /balance\.availableCredits >= cost/);
    assert.match(queue, /idempotencyKey: item\.idempotencyKey/);
    assert.match(queue, /break/);
  });

  await t.test("Anthropic missing-config path refunds reservations", async () => {
    const proxy = await readFile(path.join(repoRoot, "supabase/functions/ai-proxy/index.ts"), "utf8");

    assert.match(proxy, /ANTHROPIC_API_KEY/);
    assert.match(proxy, /anthropic_not_configured/);
    assert.match(proxy, /refund\(admin, ledgerID, "anthropic_not_configured"\)/);
    assert.match(proxy, /PROOFKIT_ANTHROPIC_MESSAGES_URL/);
  });

  await t.test("offline queue network simulation TODO", { skip: "Requires a Swift test target or UI automation harness; source-level guards are active in this suite." }, () => {});
});

test(
  "Proofly AI subscription, credits, provider, ledger, cost, and privacy E2E",
  { skip: hasSupabaseEnv ? false : `Missing ${requiredSupabaseEnv.join(", ")}.` },
  async (t) => {
    const client = new SupabaseE2EClient({
      supabaseURL: requiredEnv("SUPABASE_URL"),
      anonKey: requiredEnv("SUPABASE_ANON_KEY"),
      serviceRoleKey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      functionsURL: process.env.PROOFKIT_E2E_FUNCTIONS_URL,
    });
    const cleanupUsers = [];
    let mockAnthropic = null;
    let functionsProcess = null;
    let functionsBaseURL = client.functionsURL;
    let revenueCatAuthorization = process.env.PROOFKIT_E2E_REVENUECAT_AUTHORIZATION?.trim() ?? "";

    t.after(async () => {
      if (functionsProcess) {
        await stopChild(functionsProcess);
      }
      if (mockAnthropic) {
        await mockAnthropic.stop();
      }
      for (const user of cleanupUsers.reverse()) {
        await client.deleteSyntheticUser(user.id);
      }
    });

    if (edgeEnabled && !liveAIEnabled) {
      if (spawnFunctions) {
        mockAnthropic = await MockAnthropicServer.start();
        revenueCatAuthorization ||= `proofly-e2e-webhook-${runID}`;
        functionsBaseURL = await spawnLocalFunctions({
          client,
          mockURL: mockAnthropic.messagesURL,
          revenueCatAuthorization,
        });
        functionsProcess = functionsBaseURL.process;
        functionsBaseURL = functionsBaseURL.url;
      } else {
        assert.ok(
          confirmedMockEdge,
          "Set PROOFKIT_E2E_SPAWN_FUNCTIONS=true for the default mocked suite, or PROOFKIT_E2E_CONFIRM_MOCK_EDGE=true only when the target Edge Function is already pointed at a mock Anthropic endpoint.",
        );
      }
    }

    const createUser = async (label) => {
      const user = await client.createSyntheticUser(`${runID}-${label}`);
      cleanupUsers.push(user);
      return user;
    };

    await t.test("pricing table keeps credit costs, output caps, and disabled Ask AI flags", async () => {
      const rows = await client.select("ai_feature_pricing", {
        select: "feature,credit_cost,max_input_tokens,max_output_tokens,enabled",
      });
      const pricing = Object.fromEntries(rows.map((row) => [row.feature, row]));

      assertPricing(pricing.rewrite_note, 1, 450, true);
      assertPricing(pricing.timeline_summary, 2, 850, true);
      assertPricing(pricing.packet_polish, 4, 1700, true);
      assertPricing(pricing.deep_review, 10, 2400, true);
      assertPricing(pricing.ask_ai_short, 1, 450, false);
      assertPricing(pricing.ask_ai_case, 3, 900, false);
    });

    await t.test("subscription sync grants trial, weekly, monthly, and zero-credit inactive states", async () => {
      const trialUser = await createUser("trial-grant");
      await client.syncSubscription(trialUser.id, {
        plan: "trial_weekly_intro",
        status: "trialing",
        renewsIntoPlan: "weekly_pro",
      });
      const trialAccount = await client.latestSubscriptionAccount(trialUser.id);
      const trialBalance = await client.creditBalance(trialUser.id);
      assert.equal(trialAccount.plan, "trial_weekly_intro");
      assert.equal(trialAccount.status, "trialing");
      assert.equal(trialAccount.renews_into_plan, "weekly_pro");
      assert.equal(trialAccount.unlimited_cases, true);
      assert.equal(trialAccount.ai_credit_allowance, 3);
      assert.equal(trialBalance.credits_granted, 3);
      assert.equal(trialBalance.credits_remaining, 3);

      const weeklyUser = await createUser("weekly-grant");
      await client.syncSubscription(weeklyUser.id, { plan: "weekly_pro", status: "active_weekly" });
      assert.equal((await client.latestSubscriptionAccount(weeklyUser.id)).ai_credit_allowance, 15);
      assert.equal((await client.creditBalance(weeklyUser.id)).credits_granted, 15);

      const monthlyUser = await createUser("monthly-grant");
      await client.syncSubscription(monthlyUser.id, { plan: "monthly_pro", status: "active_monthly" });
      assert.equal((await client.latestSubscriptionAccount(monthlyUser.id)).ai_credit_allowance, 75);
      assert.equal((await client.creditBalance(monthlyUser.id)).credits_granted, 75);

      await client.syncSubscription(trialUser.id, { plan: "weekly_pro", status: "expired" });
      const expiredBalance = await client.creditBalance(trialUser.id);
      assert.equal((await client.latestSubscriptionAccount(trialUser.id)).status, "expired");
      assert.equal(expiredBalance.credits_granted, 0);
      assert.equal(expiredBalance.credits_reserved, 0);
      assert.equal(expiredBalance.credits_used, 0);
      await assert.rejects(
        () => client.reserveAI(trialUser.id, "rewrite_note", { idempotencyKey: `${runID}-expired-reserve` }),
        /no_active_ai_entitlement|ai_credit_period_inactive|insufficient_ai_credits/,
      );
    });

    await t.test("credit reservation handles allowed trial actions, blocking, concurrency, ledger, and idempotency", async () => {
      const user = await createUser("reservation");
      await client.syncSubscription(user.id, {
        plan: "trial_weekly_intro",
        status: "trialing",
        renewsIntoPlan: "weekly_pro",
      });

      const rewrite = await client.reserveAI(user.id, "rewrite_note", {
        idempotencyKey: `${runID}-reserve-rewrite`,
      });
      assert.equal(rewrite.credits_reserved, 1);
      assert.equal(rewrite.remaining_credits, 2);
      assert.equal((await client.ledgerByID(rewrite.ledger_id)).status, "pending");
      assert.equal((await client.creditBalance(user.id)).credits_reserved, 1);

      const duplicatePending = await client.reserveAI(user.id, "rewrite_note", {
        idempotencyKey: `${runID}-reserve-rewrite`,
      });
      assert.equal(duplicatePending.ledger_id, rewrite.ledger_id);
      assert.equal((await client.creditBalance(user.id)).credits_reserved, 1);
      report.summaryNotes.duplicateIdempotencyCallsBlocked += 1;

      const timeline = await client.reserveAI(user.id, "timeline_summary", {
        idempotencyKey: `${runID}-reserve-timeline`,
      });
      assert.equal(timeline.credits_reserved, 2);
      assert.equal((await client.creditBalance(user.id)).credits_reserved, 3);

      const blockingUser = await createUser("reservation-blocked");
      await client.syncSubscription(blockingUser.id, {
        plan: "trial_weekly_intro",
        status: "trialing",
        renewsIntoPlan: "weekly_pro",
      });
      await assert.rejects(
        () => client.reserveAI(blockingUser.id, "packet_polish", { idempotencyKey: `${runID}-packet-block` }),
        /insufficient_ai_credits/,
      );
      await assert.rejects(
        () => client.reserveAI(blockingUser.id, "deep_review", { idempotencyKey: `${runID}-deep-block` }),
        /insufficient_ai_credits/,
      );

      const raceUser = await createUser("reservation-race");
      await client.syncSubscription(raceUser.id, {
        plan: "trial_weekly_intro",
        status: "trialing",
        renewsIntoPlan: "weekly_pro",
      });
      const race = await Promise.allSettled([
        client.reserveAI(raceUser.id, "timeline_summary", { idempotencyKey: `${runID}-race-a` }),
        client.reserveAI(raceUser.id, "timeline_summary", { idempotencyKey: `${runID}-race-b` }),
      ]);
      assert.equal(race.filter((result) => result.status === "fulfilled").length, 1);
      assert.equal(race.filter((result) => result.status === "rejected").length, 1);
      assert.equal((await client.creditBalance(raceUser.id)).credits_reserved, 2);
    });

    await t.test("finalize and refund move credits and ledger metadata correctly", async () => {
      const successUser = await createUser("finalize");
      await client.syncSubscription(successUser.id, {
        plan: "trial_weekly_intro",
        status: "trialing",
        renewsIntoPlan: "weekly_pro",
      });
      const before = await client.creditBalance(successUser.id);
      const reservation = await client.reserveAI(successUser.id, "rewrite_note", {
        idempotencyKey: `${runID}-finalize-success`,
      });
      await client.finalizeAI(reservation.ledger_id, {
        inputTokens: 121,
        outputTokens: 37,
        estimatedCostUSD: 0.000077,
        actualCostUSD: null,
        requestHash: sha256Hex("synthetic-request"),
        responseHash: sha256Hex("synthetic-response"),
        model: "proofly-e2e-mock-haiku",
      });
      const successLedger = await client.ledgerByID(reservation.ledger_id);
      const after = await client.creditBalance(successUser.id);
      assert.equal(successLedger.status, "succeeded");
      assert.equal(successLedger.credits_reserved, 1);
      assert.equal(successLedger.credits_charged, 1);
      assert.equal(successLedger.input_tokens, 121);
      assert.equal(successLedger.output_tokens, 37);
      assert.equal(successLedger.model, "proofly-e2e-mock-haiku");
      assert.ok(successLedger.request_hash);
      assert.ok(successLedger.response_hash);
      assert.equal(after.credits_reserved, 0);
      assert.equal(after.credits_used, before.credits_used + 1);

      const refundUser = await createUser("refund");
      await client.syncSubscription(refundUser.id, {
        plan: "trial_weekly_intro",
        status: "trialing",
        renewsIntoPlan: "weekly_pro",
      });
      const refundReservation = await client.reserveAI(refundUser.id, "timeline_summary", {
        idempotencyKey: `${runID}-refund-failure`,
      });
      await client.refundAI(refundReservation.ledger_id, "provider_503");
      const refunded = await client.ledgerByID(refundReservation.ledger_id);
      const refundBalance = await client.creditBalance(refundUser.id);
      assert.equal(refunded.status, "failed");
      assert.equal(refunded.credits_charged, 0);
      assert.equal(refunded.error_code, "provider_503");
      assert.equal(refundBalance.credits_reserved, 0);
      assert.equal(refundBalance.credits_remaining, 3);

      const sameFailedKey = await client.reserveAI(refundUser.id, "timeline_summary", {
        idempotencyKey: `${runID}-refund-failure`,
      });
      assert.equal(sameFailedKey.ledger_id, refundReservation.ledger_id);
      assert.equal((await client.creditBalance(refundUser.id)).credits_reserved, 0);
    });

    await t.test(
      "RevenueCat webhook maps synthetic trial, weekly, monthly, expiration, and refund events",
      { skip: edgeEnabled ? false : "Set PROOFKIT_E2E_SPAWN_FUNCTIONS=true or another Edge mode to run webhook integration." },
      async () => {
        const webhookUser = await createUser("revenuecat");
        const now = Date.now();

        await client.invokeFunction(
          "revenuecat-webhook",
          {
            event: {
              id: `${runID}-rc-trial`,
              type: "INITIAL_PURCHASE",
              app_user_id: webhookUser.id,
              original_app_user_id: webhookUser.id,
              product_id: "proofly_weekly_pro",
              entitlement_id: "pro",
              period_type: "TRIAL",
              purchased_at_ms: now,
              expiration_at_ms: now + 7 * 24 * 60 * 60 * 1000,
            },
          },
          { functionsBaseURL, authorization: revenueCatAuthorization },
        );
        assert.equal((await client.latestSubscriptionAccount(webhookUser.id)).plan, "trial_weekly_intro");
        assert.equal((await client.latestSubscriptionAccount(webhookUser.id)).status, "trialing");
        assert.equal((await client.latestSubscriptionAccount(webhookUser.id)).renews_into_plan, "weekly_pro");
        assert.equal((await client.creditBalance(webhookUser.id)).credits_granted, 3);

        await client.invokeFunction(
          "revenuecat-webhook",
          {
            event: {
              id: `${runID}-rc-weekly`,
              type: "RENEWAL",
              app_user_id: webhookUser.id,
              original_app_user_id: webhookUser.id,
              product_id: "proofly_weekly_pro",
              entitlement_id: "pro",
              period_type: "NORMAL",
              purchased_at_ms: now + 1,
              expiration_at_ms: now + 7 * 24 * 60 * 60 * 1000,
            },
          },
          { functionsBaseURL, authorization: revenueCatAuthorization },
        );
        assert.equal((await client.latestSubscriptionAccount(webhookUser.id)).plan, "weekly_pro");
        assert.equal((await client.creditBalance(webhookUser.id)).credits_granted, 15);

        await client.invokeFunction(
          "revenuecat-webhook",
          {
            event: {
              id: `${runID}-rc-monthly`,
              type: "RENEWAL",
              app_user_id: webhookUser.id,
              original_app_user_id: webhookUser.id,
              product_id: "proofly_monthly_pro",
              entitlement_id: "pro",
              period_type: "NORMAL",
              purchased_at_ms: now + 2,
              expiration_at_ms: now + 31 * 24 * 60 * 60 * 1000,
            },
          },
          { functionsBaseURL, authorization: revenueCatAuthorization },
        );
        assert.equal((await client.latestSubscriptionAccount(webhookUser.id)).plan, "monthly_pro");
        assert.equal((await client.creditBalance(webhookUser.id)).credits_granted, 75);

        await client.invokeFunction(
          "revenuecat-webhook",
          {
            event: {
              id: `${runID}-rc-expiration`,
              type: "EXPIRATION",
              app_user_id: webhookUser.id,
              original_app_user_id: webhookUser.id,
              product_id: "proofly_monthly_pro",
              entitlement_id: "pro",
              period_type: "NORMAL",
              purchased_at_ms: now + 3,
              expiration_at_ms: now + 4,
            },
          },
          { functionsBaseURL, authorization: revenueCatAuthorization },
        );
        assert.equal((await client.latestSubscriptionAccount(webhookUser.id)).status, "expired");
        assert.equal((await client.creditBalance(webhookUser.id)).credits_granted, 0);

        await client.invokeFunction(
          "revenuecat-webhook",
          {
            event: {
              id: `${runID}-rc-refund`,
              type: "REFUND",
              app_user_id: webhookUser.id,
              original_app_user_id: webhookUser.id,
              product_id: "proofly_weekly_pro",
              entitlement_id: "pro",
              period_type: "NORMAL",
              purchased_at_ms: now + 5,
              expiration_at_ms: now + 7 * 24 * 60 * 60 * 1000,
            },
          },
          { functionsBaseURL, authorization: revenueCatAuthorization },
        );
        assert.equal((await client.latestSubscriptionAccount(webhookUser.id)).status, "revoked_or_refunded");
        assert.equal((await client.creditBalance(webhookUser.id)).credits_granted, 0);
      },
    );

    await t.test(
      "ai-proxy performs quote-costed mocked AI runs, idempotency blocking, refunds, caps, and disabled feature checks",
      { skip: edgeEnabled ? false : "Set PROOFKIT_E2E_SPAWN_FUNCTIONS=true for default mocked Edge tests, or LIVE_AI_E2E=true for the tiny live suite." },
      async (edgeT) => {
        const apartment = fixtures.apartment_issue;
        const work = fixtures.freelance_work_issue;
        const user = await createUser("edge-ai");
        await client.syncSubscription(user.id, {
          plan: "trial_weekly_intro",
          status: "trialing",
          renewsIntoPlan: "weekly_pro",
        });

        const timelineBefore = await client.creditBalance(user.id);
        const timeline = await client.invokeAIProxy(user, {
          feature: "timeline_summary",
          taskType: "summarizeTimeline",
          caseID: randomUUID(),
          compressedTextInput: apartment.promptText,
          metadata: { source: "e2e", fixture: apartment.fixtureID },
          idempotencyKey: `${runID}-edge-timeline`,
          functionsBaseURL,
        });
        assert.equal(timeline.status, 200);
        assert.ok(timeline.data.outputText);
        assert.equal(timeline.data.creditsUsed, 2);
        assert.equal(timeline.data.remainingCredits, 1);
        await recordLedgerEntry(client, report, user.id, timeline.data.resultID, {
          feature: "timeline_summary",
          plan: "trial_weekly_intro",
          status: "trialing",
          creditsBefore: timelineBefore.credits_remaining,
          latencyMs: timeline.latencyMs,
          truncationMetadata: timeline.data.metadata,
        });

        const cleanupBefore = await client.creditBalance(user.id);
        const cleanup = await client.invokeAIProxy(user, {
          feature: "rewrite_note",
          taskType: "rewriteNote",
          caseID: randomUUID(),
          evidenceItemID: randomUUID(),
          compressedTextInput: `${work.promptText}\nUser note to clean up: ${work.notes[0]}`,
          metadata: { source: "e2e", fixture: work.fixtureID },
          idempotencyKey: `${runID}-edge-rewrite`,
          functionsBaseURL,
        });
        assert.equal(cleanup.status, 200);
        assert.ok(cleanup.data.outputText);
        assert.equal(cleanup.data.creditsUsed, 1);
        assert.equal(cleanup.data.remainingCredits, 0);
        await recordLedgerEntry(client, report, user.id, cleanup.data.resultID, {
          feature: "rewrite_note",
          plan: "trial_weekly_intro",
          status: "trialing",
          creditsBefore: cleanupBefore.credits_remaining,
          latencyMs: cleanup.latencyMs,
          truncationMetadata: cleanup.data.metadata,
        });

        const blockedUser = await createUser("edge-blocked");
        await client.syncSubscription(blockedUser.id, {
          plan: "trial_weekly_intro",
          status: "trialing",
          renewsIntoPlan: "weekly_pro",
        });
        const beforeBlockedProviderCalls = mockAnthropic?.callCount ?? null;
        const packet = await client.invokeAIProxy(blockedUser, {
          feature: "packet_polish",
          taskType: "finalCaseNarrative",
          caseID: randomUUID(),
          compressedTextInput: fixtures.refund_fight.promptText,
          idempotencyKey: `${runID}-edge-packet-block`,
          functionsBaseURL,
          allowError: true,
        });
        assert.equal(packet.status, 400);
        assert.match(JSON.stringify(packet.data), /insufficient_ai_credits/);

        const deep = await client.invokeAIProxy(blockedUser, {
          feature: "deep_review",
          taskType: "classifyEvidence",
          caseID: randomUUID(),
          compressedTextInput: fixtures.school_college_issue.promptText,
          idempotencyKey: `${runID}-edge-deep-block`,
          functionsBaseURL,
          allowError: true,
        });
        assert.equal(deep.status, 400);
        assert.match(JSON.stringify(deep.data), /insufficient_ai_credits/);
        if (mockAnthropic) assert.equal(mockAnthropic.callCount, beforeBlockedProviderCalls);

        for (const feature of ["ask_ai_short", "ask_ai_case"]) {
          const disabled = await client.invokeAIProxy(blockedUser, {
            feature,
            taskType: "summarizeItem",
            caseID: randomUUID(),
            compressedTextInput: "Synthetic disabled Ask AI input.",
            idempotencyKey: `${runID}-edge-disabled-${feature}`,
            functionsBaseURL,
            allowError: true,
          });
          assert.equal(disabled.status, 403);
          assert.match(JSON.stringify(disabled.data), /ai_feature_disabled/);
        }

        await edgeT.test(
          "duplicate idempotency keys do not call provider again",
          { skip: mockAnthropic ? false : "Provider call counting is only available in mocked Edge mode." },
          async () => {
            const pendingUser = await createUser("edge-duplicate-pending");
            await client.syncSubscription(pendingUser.id, {
              plan: "trial_weekly_intro",
              status: "trialing",
              renewsIntoPlan: "weekly_pro",
            });
            const pendingKey = `${runID}-edge-dup-pending`;
            await client.reserveAI(pendingUser.id, "rewrite_note", { idempotencyKey: pendingKey });
            const callsBeforePendingDuplicate = mockAnthropic.callCount;
            const duplicatePending = await client.invokeAIProxy(pendingUser, {
              feature: "rewrite_note",
              taskType: "rewriteNote",
              caseID: randomUUID(),
              compressedTextInput: "Synthetic duplicate pending input.",
              idempotencyKey: pendingKey,
              functionsBaseURL,
              allowError: true,
            });
            assert.equal(duplicatePending.status, 409);
            assert.equal(duplicatePending.data.error, "request_already_pending");
            assert.equal(mockAnthropic.callCount, callsBeforePendingDuplicate);
            report.summaryNotes.duplicateIdempotencyCallsBlocked += 1;

            const callsBeforeCompletedDuplicate = mockAnthropic.callCount;
            const duplicateCompleted = await client.invokeAIProxy(user, {
              feature: "timeline_summary",
              taskType: "summarizeTimeline",
              caseID: randomUUID(),
              compressedTextInput: apartment.promptText,
              idempotencyKey: `${runID}-edge-timeline`,
              functionsBaseURL,
              allowError: true,
            });
            assert.equal(duplicateCompleted.status, 409);
            assert.equal(duplicateCompleted.data.error, "duplicate_already_completed");
            assert.equal(mockAnthropic.callCount, callsBeforeCompletedDuplicate);
            report.summaryNotes.duplicateIdempotencyCallsBlocked += 1;
          },
        );

        await edgeT.test(
          "provider failures and empty outputs refund credits",
          { skip: mockAnthropic ? false : "Failure and empty-output tests use the mock Anthropic server." },
          async () => {
            const failureUser = await createUser("edge-failure");
            await client.syncSubscription(failureUser.id, {
              plan: "trial_weekly_intro",
              status: "trialing",
              renewsIntoPlan: "weekly_pro",
            });

            const failedKey = `${runID}-edge-provider-failure`;
            const providerFailure = await client.invokeAIProxy(failureUser, {
              feature: "rewrite_note",
              taskType: "rewriteNote",
              caseID: randomUUID(),
              evidenceItemID: randomUUID(),
              compressedTextInput: `MOCK_PROVIDER_503 ${fixtures.refund_fight.promptText}`,
              idempotencyKey: failedKey,
              functionsBaseURL,
              allowError: true,
            });
            assert.equal(providerFailure.status, 502);
            assert.equal(providerFailure.data.error, "ai_provider_failed");
            const failedLedger = await client.ledgerByIdempotencyKey(failureUser.id, failedKey);
            assert.equal(failedLedger.status, "failed");
            assert.equal(failedLedger.credits_charged, 0);
            assert.equal(failedLedger.error_code, "anthropic_503");
            assert.equal((await client.creditBalance(failureUser.id)).credits_remaining, 3);

            const callsBeforeFailedDuplicate = mockAnthropic.callCount;
            const failedDuplicate = await client.invokeAIProxy(failureUser, {
              feature: "rewrite_note",
              taskType: "rewriteNote",
              caseID: randomUUID(),
              evidenceItemID: randomUUID(),
              compressedTextInput: fixtures.refund_fight.promptText,
              idempotencyKey: failedKey,
              functionsBaseURL,
              allowError: true,
            });
            assert.equal(failedDuplicate.status, 409);
            assert.equal(failedDuplicate.data.error, "idempotency_key_already_finalized_use_new_key");
            assert.equal(mockAnthropic.callCount, callsBeforeFailedDuplicate);
            report.summaryNotes.duplicateIdempotencyCallsBlocked += 1;

            const emptyKey = `${runID}-edge-empty-response`;
            const empty = await client.invokeAIProxy(failureUser, {
              feature: "rewrite_note",
              taskType: "rewriteNote",
              caseID: randomUUID(),
              evidenceItemID: randomUUID(),
              compressedTextInput: `MOCK_EMPTY_PROVIDER_RESPONSE ${fixtures.school_college_issue.promptText}`,
              idempotencyKey: emptyKey,
              functionsBaseURL,
              allowError: true,
            });
            assert.equal(empty.status, 502);
            assert.equal(empty.data.error, "empty_ai_output");
            const emptyLedger = await client.ledgerByIdempotencyKey(failureUser.id, emptyKey);
            assert.equal(emptyLedger.status, "failed");
            assert.equal(emptyLedger.credits_charged, 0);
            assert.equal(emptyLedger.error_code, "empty_ai_output");
            assert.equal((await client.creditBalance(failureUser.id)).credits_remaining, 3);
          },
        );

        await edgeT.test(
          "input truncation, max output tokens, and cost fields are measurable",
          { skip: mockAnthropic ? false : "Token cap assertions inspect mock provider requests." },
          async () => {
            const monthlyUser = await createUser("edge-caps");
            await client.syncSubscription(monthlyUser.id, { plan: "monthly_pro", status: "active_monthly" });
            const hugeTail = "HUGE_SYNTHETIC_TAIL_SHOULD_NOT_REACH_PROVIDER";
            const hugeInput = `HUGE_SYNTHETIC_INPUT_START ${"A".repeat(20_000)} ${hugeTail}`;
            const beforeHuge = await client.creditBalance(monthlyUser.id);
            const huge = await client.invokeAIProxy(monthlyUser, {
              feature: "rewrite_note",
              taskType: "rewriteNote",
              caseID: randomUUID(),
              evidenceItemID: randomUUID(),
              compressedTextInput: hugeInput,
              idempotencyKey: `${runID}-edge-huge-rewrite`,
              functionsBaseURL,
            });
            assert.equal(huge.status, 200);
            assert.equal(huge.data.metadata.inputTruncated, "true");
            assert.equal(huge.data.metadata.inputCharacterLimit, "9000");
            assert.equal(huge.data.metadata.originalInputCharacters, String(hugeInput.length));
            assert.equal(JSON.stringify(mockAnthropic.lastCall.body).includes(hugeTail), false);
            await recordLedgerEntry(client, report, monthlyUser.id, huge.data.resultID, {
              feature: "rewrite_note",
              plan: "monthly_pro",
              status: "active_monthly",
              creditsBefore: beforeHuge.credits_remaining,
              latencyMs: huge.latencyMs,
              truncationMetadata: huge.data.metadata,
            });

            const featuresToCaps = [
              ["timeline_summary", "summarizeTimeline", 850],
              ["packet_polish", "finalCaseNarrative", 1700],
              ["deep_review", "classifyEvidence", 2400],
            ];
            for (const [feature, taskType, expectedMaxTokens] of featuresToCaps) {
              const callIndex = mockAnthropic.callCount;
              const response = await client.invokeAIProxy(monthlyUser, {
                feature,
                taskType,
                caseID: randomUUID(),
                compressedTextInput: `Synthetic cap-check input for ${feature}.`,
                idempotencyKey: `${runID}-edge-cap-${feature}`,
                functionsBaseURL,
              });
              assert.equal(response.status, 200);
              const providerCall = mockAnthropic.calls[callIndex];
              assert.ok(providerCall, `Expected mock call for ${feature}`);
              assert.equal(providerCall.body.max_tokens, expectedMaxTokens);
            }
          },
        );

        if (liveAIEnabled) {
          await edgeT.test("live AI suite is intentionally tiny", async () => {
            assert.equal(liveAIEnabled, true);
            assert.ok(timeline.data.outputText);
            assert.ok(cleanup.data.outputText);
          });
        }
      },
    );

    await t.test("privacy leak assertions inspect remote metadata/accounting tables", async () => {
      const forbidden = forbiddenFixtureStrings(fixtures);
      const tableNames = [
        "ai_usage_ledger",
        "ai_credit_balances",
        "subscription_accounts",
        ...optionalTableNames(process.env.PROOFKIT_E2E_ANALYTICS_TABLES),
      ];
      const leaks = [];
      for (const tableName of tableNames) {
        const rows = await client.trySelect(tableName, { select: "*", limit: "1000" });
        if (!rows) continue;
        const serialized = JSON.stringify(rows);
        for (const value of forbidden) {
          if (value && serialized.includes(value)) {
            leaks.push({ table: tableName, value });
          }
        }
      }
      report.privacyLeakCheck = { passed: leaks.length === 0, leaks };
      assert.deepEqual(leaks, []);
    });
  },
);

function assertPricing(row, creditCost, maxOutputTokens, enabled) {
  assert.ok(row);
  assert.equal(row.credit_cost, creditCost);
  assert.equal(row.max_output_tokens, maxOutputTokens);
  assert.equal(row.enabled, enabled);
}

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function sha256Hex(text) {
  return createHash("sha256").update(text).digest("hex");
}

function optionalTableNames(value) {
  return (value ?? "")
    .split(",")
    .map((name) => name.trim())
    .filter(Boolean);
}

function forbiddenFixtureStrings(fixtureRoot) {
  const values = new Set(["SYNTHETIC_AI_OUTPUT_SENTINEL"]);
  const visit = (value) => {
    if (typeof value === "string") {
      if (value.length >= 12) values.add(value);
      return;
    }
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    if (value && typeof value === "object") {
      Object.values(value).forEach(visit);
    }
  };
  visit(fixtureRoot);
  return [...values];
}

async function recordLedgerEntry(client, usageReport, userID, ledgerID, context) {
  const ledger = await client.ledgerByID(ledgerID);
  const after = await client.creditBalance(userID);
  usageReport.addEntry({
    timestamp: new Date().toISOString(),
    testUserIDHash: sha256Hex(userID).slice(0, 16),
    feature: context.feature,
    plan: context.plan,
    subscriptionStatus: context.status,
    creditsBefore: context.creditsBefore,
    creditsReserved: ledger.credits_reserved,
    creditsCharged: ledger.credits_charged,
    creditsAfter: after.credits_remaining,
    provider: ledger.provider,
    model: ledger.model,
    inputTokens: ledger.input_tokens,
    outputTokens: ledger.output_tokens,
    estimatedCostUSD: decimalOrNull(ledger.estimated_cost_usd),
    actualCostUSD: decimalOrNull(ledger.actual_cost_usd),
    costNullReason: ledger.estimated_cost_usd == null
      ? "Cost env vars or provider token counts were unavailable to the Edge Function."
      : null,
    latencyMs: context.latencyMs,
    ledgerID: ledger.id,
    status: ledger.status,
    truncationMetadata: context.truncationMetadata ?? {},
    marginEstimate: marginEstimate(context.plan, ledger.credits_charged, decimalOrNull(ledger.estimated_cost_usd)),
  });
}

function decimalOrNull(value) {
  if (value == null) return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function marginEstimate(plan, creditsCharged, estimatedCostUSD) {
  const weeklyPrice = Number(process.env.PROOFKIT_E2E_WEEKLY_PRICE_USD ?? "3.99");
  const monthlyPrice = Number(process.env.PROOFKIT_E2E_MONTHLY_PRICE_USD ?? "9.99");
  const revenuePerCredit = {
    trial_weekly_intro: 0,
    weekly_pro: weeklyPrice / 15,
    monthly_pro: monthlyPrice / 75,
  }[plan] ?? null;
  if (revenuePerCredit == null || estimatedCostUSD == null) {
    return {
      revenuePerCreditUSD: revenuePerCredit,
      estimatedRevenueUSD: revenuePerCredit == null ? null : roundUSD(revenuePerCredit * creditsCharged),
      estimatedGrossMarginUSD: null,
      estimatedGrossMarginPercent: null,
    };
  }
  const revenue = revenuePerCredit * creditsCharged;
  const margin = revenue - estimatedCostUSD;
  return {
    revenuePerCreditUSD: roundUSD(revenuePerCredit),
    estimatedRevenueUSD: roundUSD(revenue),
    estimatedGrossMarginUSD: roundUSD(margin),
    estimatedGrossMarginPercent: revenue > 0 ? Math.round((margin / revenue) * 10000) / 100 : null,
  };
}

function roundUSD(value) {
  return Math.round(value * 1_000_000) / 1_000_000;
}

async function spawnLocalFunctions({ client, mockURL, revenueCatAuthorization }) {
  const envDir = path.join(repoRoot, ".tmp");
  await mkdir(envDir, { recursive: true });
  const envFile = path.join(envDir, `proofly-e2e-functions-${process.pid}.env`);
  await writeFile(
    envFile,
    [
      `SUPABASE_URL=${client.supabaseURL}`,
      `SUPABASE_ANON_KEY=${client.anonKey}`,
      `SUPABASE_SERVICE_ROLE_KEY=${client.serviceRoleKey}`,
      "ANTHROPIC_API_KEY=proofly-e2e-mock-key",
      `PROOFKIT_ANTHROPIC_MESSAGES_URL=${mockURL}`,
      "PROOFKIT_ANTHROPIC_HAIKU_MODEL=proofly-e2e-mock-haiku",
      "PROOFKIT_AI_INPUT_COST_PER_MILLION_USD=0.25",
      "PROOFKIT_AI_OUTPUT_COST_PER_MILLION_USD=1.25",
      `REVENUECAT_WEBHOOK_AUTHORIZATION=${revenueCatAuthorization}`,
      "",
    ].join("\n"),
    { mode: 0o600 },
  );

  const child = spawn("supabase", ["functions", "serve", "--no-verify-jwt", "--env-file", envFile], {
    cwd: repoRoot,
    env: { ...process.env },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    output += chunk.toString();
  });
  const url = process.env.PROOFKIT_E2E_LOCAL_FUNCTIONS_URL ?? "http://127.0.0.1:54321/functions/v1";
  await waitForFunctionServer(url, child, () => output);
  return { url, process: child };
}

async function stopChild(child) {
  if (child.exitCode != null) return;
  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolve) => child.once("exit", resolve)),
    new Promise((resolve) => setTimeout(resolve, 5_000)),
  ]);
  if (child.exitCode == null) child.kill("SIGKILL");
}

async function waitForFunctionServer(functionsURL, child, output) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (child.exitCode != null) {
      throw new Error(`supabase functions serve exited early:\n${output()}`);
    }
    try {
      const response = await fetch(`${functionsURL}/ai-credit-balance`, { method: "OPTIONS" });
      if (response.ok || response.status === 401 || response.status === 400) return;
    } catch (_) {
      // Keep waiting.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Timed out waiting for local Edge Functions:\n${output()}`);
}

class SupabaseE2EClient {
  constructor({ supabaseURL, anonKey, serviceRoleKey, functionsURL }) {
    this.supabaseURL = supabaseURL.replace(/\/$/, "");
    this.anonKey = anonKey;
    this.serviceRoleKey = serviceRoleKey;
    this.functionsURL = (functionsURL?.replace(/\/$/, "") ?? `${this.supabaseURL}/functions/v1`);
  }

  serviceHeaders(extra = {}) {
    return {
      apikey: this.serviceRoleKey,
      authorization: `Bearer ${this.serviceRoleKey}`,
      ...extra,
    };
  }

  anonHeaders(extra = {}) {
    return {
      apikey: this.anonKey,
      ...extra,
    };
  }

  async createSyntheticUser(label) {
    const email = `${label.replace(/[^a-zA-Z0-9.-]/g, "-").toLowerCase()}@synthetic.invalid`;
    const password = `Proofly-E2E-${randomUUID()}!`;
    const create = await requestJSON(`${this.supabaseURL}/auth/v1/admin/users`, {
      method: "POST",
      headers: this.serviceHeaders(),
      body: {
        email,
        password,
        email_confirm: true,
        user_metadata: {
          proofly_e2e: true,
          run_id: runID,
        },
      },
    });
    const id = create.data?.id;
    assert.ok(id, "Expected synthetic auth user id");
    const signIn = await requestJSON(`${this.supabaseURL}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: this.anonHeaders(),
      body: { email, password },
    });
    assert.ok(signIn.data?.access_token, "Expected synthetic user access token");
    return { id, email, password, accessToken: signIn.data.access_token };
  }

  async deleteSyntheticUser(userID) {
    await requestJSON(`${this.supabaseURL}/auth/v1/admin/users/${userID}`, {
      method: "DELETE",
      headers: this.serviceHeaders(),
      allowError: true,
    });
  }

  async rpc(name, body) {
    const response = await requestJSON(`${this.supabaseURL}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: this.serviceHeaders({ accept: "application/json" }),
      body,
    });
    return response.data;
  }

  async select(table, query = {}) {
    const url = new URL(`${this.supabaseURL}/rest/v1/${table}`);
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, String(value));
    }
    const response = await requestJSON(url, {
      headers: this.serviceHeaders({ accept: "application/json" }),
    });
    return response.data ?? [];
  }

  async trySelect(table, query = {}) {
    try {
      return await this.select(table, query);
    } catch (error) {
      if (error instanceof HTTPError && [404, 406].includes(error.status)) return null;
      throw error;
    }
  }

  async syncSubscription(userID, { plan, status, renewsIntoPlan = null }) {
    const now = Date.now();
    const periodStart = new Date(now + Math.floor(Math.random() * 1000)).toISOString();
    const periodEnd = new Date(now + (plan === "monthly_pro" ? 31 : 7) * 24 * 60 * 60 * 1000).toISOString();
    return this.rpc("proofkit_sync_subscription_account", {
      p_user_id: userID,
      p_provider_customer_id: `proofly-e2e-${userID}`,
      p_entitlement_id: "pro",
      p_plan: plan,
      p_status: status,
      p_current_period_start: periodStart,
      p_current_period_end: periodEnd,
      p_trial_ends_at: status === "trialing" ? periodEnd : null,
      p_renews_into_plan: renewsIntoPlan,
      p_source_event_id: `${runID}-${plan}-${status}`,
    });
  }

  async latestSubscriptionAccount(userID) {
    const rows = await this.select("subscription_accounts", {
      select: "*",
      user_id: `eq.${userID}`,
      order: "updated_at.desc",
      limit: "1",
    });
    assert.ok(rows[0], `Expected subscription account for ${userID}`);
    return rows[0];
  }

  async creditBalance(userID) {
    const rows = await this.select("ai_credit_balances", {
      select: "*",
      user_id: `eq.${userID}`,
      limit: "1",
    });
    return rows[0] ?? {
      credits_granted: 0,
      credits_reserved: 0,
      credits_used: 0,
      credits_remaining: 0,
    };
  }

  async reserveAI(userID, feature, { idempotencyKey, caseID = randomUUID() } = {}) {
    const data = await this.rpc("proofkit_reserve_ai_credits", {
      p_user_id: userID,
      p_feature: feature,
      p_case_id: caseID,
      p_idempotency_key: idempotencyKey ?? randomUUID(),
    });
    return Array.isArray(data) ? data[0] : data;
  }

  async finalizeAI(ledgerID, options) {
    return this.rpc("proofkit_finalize_ai_usage", {
      p_ledger_id: ledgerID,
      p_input_tokens: options.inputTokens,
      p_output_tokens: options.outputTokens,
      p_estimated_cost_usd: options.estimatedCostUSD,
      p_actual_cost_usd: options.actualCostUSD,
      p_request_hash: options.requestHash,
      p_response_hash: options.responseHash,
      p_model: options.model,
    });
  }

  async refundAI(ledgerID, errorCode) {
    return this.rpc("proofkit_refund_ai_reservation", {
      p_ledger_id: ledgerID,
      p_error_code: errorCode,
    });
  }

  async ledgerByID(ledgerID) {
    const rows = await this.select("ai_usage_ledger", {
      select: "*",
      id: `eq.${ledgerID}`,
      limit: "1",
    });
    assert.ok(rows[0], `Expected ledger ${ledgerID}`);
    return rows[0];
  }

  async ledgerByIdempotencyKey(userID, idempotencyKey) {
    const rows = await this.select("ai_usage_ledger", {
      select: "*",
      user_id: `eq.${userID}`,
      idempotency_key: `eq.${idempotencyKey}`,
      order: "created_at.desc",
      limit: "1",
    });
    assert.ok(rows[0], `Expected ledger for idempotency key ${idempotencyKey}`);
    return rows[0];
  }

  async invokeFunction(name, body, { functionsBaseURL = this.functionsURL, accessToken = null, authorization = null, allowError = false } = {}) {
    const headers = {
      apikey: this.anonKey,
      ...(accessToken ? { authorization: `Bearer ${accessToken}` } : {}),
      ...(authorization ? { authorization: authorization.startsWith("Bearer ") ? authorization : `Bearer ${authorization}` } : {}),
    };
    return requestJSON(`${functionsBaseURL.replace(/\/$/, "")}/${name}`, {
      method: "POST",
      headers,
      body,
      allowError,
    });
  }

  async invokeAIProxy(user, options) {
    const startedAt = Date.now();
    const body = {
      feature: options.feature,
      taskType: options.taskType,
      compressedTextInput: options.compressedTextInput,
      inputHash: sha256Hex(`${options.feature}\n${options.compressedTextInput}\n${options.idempotencyKey}`),
      caseID: options.caseID,
      evidenceItemID: options.evidenceItemID ?? null,
      evidenceItemIDs: options.evidenceItemID ? [options.evidenceItemID] : [],
      extractedTextSnippets: [options.compressedTextInput],
      metadata: options.metadata ?? {},
      userTriggered: true,
      idempotencyKey: options.idempotencyKey,
    };
    const response = await this.invokeFunction("ai-proxy", body, {
      functionsBaseURL: options.functionsBaseURL,
      accessToken: user.accessToken,
      allowError: options.allowError,
    });
    response.latencyMs = Date.now() - startedAt;
    return response;
  }
}

class HTTPError extends Error {
  constructor(message, { status, data, text }) {
    super(message);
    this.name = "HTTPError";
    this.status = status;
    this.data = data;
    this.text = text;
  }
}

async function requestJSON(urlLike, { method = "GET", headers = {}, body, allowError = false } = {}) {
  const response = await fetch(urlLike, {
    method,
    headers: {
      ...(body === undefined ? {} : { "content-type": "application/json" }),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = text;
    }
  }
  if (!response.ok && !allowError) {
    throw new HTTPError(`${method} ${urlLike} failed with ${response.status}: ${text}`, {
      status: response.status,
      data,
      text,
    });
  }
  return { ok: response.ok, status: response.status, data, text, headers: response.headers };
}

class MockAnthropicServer {
  constructor(server) {
    this.server = server;
    this.calls = [];
  }

  static async start() {
    const mock = new MockAnthropicServer(null);
    const server = createServer(async (req, res) => {
      if (req.method === "GET" && req.url === "/__proofly/calls") {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ calls: mock.calls }));
        return;
      }
      if (req.method !== "POST" || req.url !== "/v1/messages") {
        res.writeHead(404, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "not_found" }));
        return;
      }

      const bodyText = await readRequestBody(req);
      const body = JSON.parse(bodyText || "{}");
      const promptText = JSON.stringify(body);
      const idempotencyKey = extractIdempotencyKey(promptText);
      const feature = extractFeature(promptText);
      const call = {
        at: new Date().toISOString(),
        feature,
        idempotencyKey,
        body,
      };
      mock.calls.push(call);

      if (promptText.includes("MOCK_PROVIDER_503")) {
        res.writeHead(503, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: { type: "overloaded_error", message: "Synthetic provider failure" } }));
        return;
      }

      if (promptText.includes("MOCK_EMPTY_PROVIDER_RESPONSE")) {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ content: [], usage: { input_tokens: estimateTokens(promptText), output_tokens: 0 } }));
        return;
      }

      const outputText = `SYNTHETIC_AI_OUTPUT_SENTINEL ${feature} mock response ${mock.calls.length}`;
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({
        id: `msg_${mock.calls.length}`,
        type: "message",
        role: "assistant",
        model: body.model ?? "proofly-e2e-mock-haiku",
        content: [{ type: "text", text: outputText }],
        usage: {
          input_tokens: estimateTokens(promptText),
          output_tokens: estimateTokens(outputText),
        },
      }));
    });
    mock.server = server;
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    return mock;
  }

  get port() {
    return this.server.address().port;
  }

  get messagesURL() {
    return `http://127.0.0.1:${this.port}/v1/messages`;
  }

  get callCount() {
    return this.calls.length;
  }

  get lastCall() {
    return this.calls[this.calls.length - 1] ?? null;
  }

  async stop() {
    await new Promise((resolve) => this.server.close(resolve));
  }
}

async function readRequestBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

function estimateTokens(text) {
  return Math.max(1, Math.ceil(text.length / 4));
}

function extractFeature(text) {
  if (text.includes("Timeline Summary")) return "timeline_summary";
  if (text.includes("Clean Up Note")) return "rewrite_note";
  if (text.includes("Packet Polish")) return "packet_polish";
  if (text.includes("Deep Review")) return "deep_review";
  if (text.includes("Ask AI with Case Context")) return "ask_ai_case";
  if (text.includes("Ask AI")) return "ask_ai_short";
  return "unknown";
}

function extractIdempotencyKey(text) {
  const match = text.match(/proofly-e2e-[a-zA-Z0-9-]+/);
  return match?.[0] ?? null;
}

class UsageReport {
  constructor(id) {
    this.id = id;
    this.startedAt = new Date().toISOString();
    this.entries = [];
    this.privacyLeakCheck = { passed: null, leaks: [] };
    this.summaryNotes = {
      duplicateIdempotencyCallsBlocked: 0,
      skippedBecauseMissingEnv: hasSupabaseEnv ? [] : requiredSupabaseEnv.filter((name) => !process.env[name]?.trim()),
      liveAIEnabled,
      mockedAIByDefault: !liveAIEnabled,
    };
  }

  addEntry(entry) {
    this.entries.push(entry);
  }

  summary() {
    const totalCreditsCharged = this.entries.reduce((sum, entry) => sum + (entry.creditsCharged ?? 0), 0);
    const totalEstimatedProviderCost = this.entries.reduce((sum, entry) => sum + (entry.estimatedCostUSD ?? 0), 0);
    const failedOrRefunded = this.entries.filter((entry) => ["failed", "refunded"].includes(entry.status));
    const highestCostFeature = [...this.entries]
      .sort((lhs, rhs) => (rhs.estimatedCostUSD ?? 0) - (lhs.estimatedCostUSD ?? 0))[0]?.feature ?? null;
    return {
      totalAICalls: this.entries.length,
      totalCreditsCharged,
      totalEstimatedProviderCostUSD: roundUSD(totalEstimatedProviderCost),
      averageCostPerCreditUSD: totalCreditsCharged > 0 ? roundUSD(totalEstimatedProviderCost / totalCreditsCharged) : null,
      highestCostFeature,
      failedOrRefundedCalls: failedOrRefunded.length,
      duplicateIdempotencyCallsBlocked: this.summaryNotes.duplicateIdempotencyCallsBlocked,
      privacyLeakTestResult: this.privacyLeakCheck,
      notes: this.summaryNotes,
    };
  }

  async write(outputDir) {
    await mkdir(outputDir, { recursive: true });
    const payload = {
      runID: this.id,
      startedAt: this.startedAt,
      finishedAt: new Date().toISOString(),
      entries: this.entries,
      summary: this.summary(),
    };
    await writeFile(
      path.join(outputDir, "ai-usage-cost-report.json"),
      `${JSON.stringify(payload, null, 2)}\n`,
    );
    await writeFile(path.join(outputDir, "ai-usage-cost-report.md"), renderMarkdownReport(payload));
  }
}

function renderMarkdownReport(payload) {
  const lines = [
    "# Proofly AI Usage Cost Report",
    "",
    `- Run ID: ${payload.runID}`,
    `- Started: ${payload.startedAt}`,
    `- Finished: ${payload.finishedAt}`,
    `- Total AI calls: ${payload.summary.totalAICalls}`,
    `- Total credits charged: ${payload.summary.totalCreditsCharged}`,
    `- Total estimated provider cost USD: ${payload.summary.totalEstimatedProviderCostUSD}`,
    `- Average cost per credit USD: ${payload.summary.averageCostPerCreditUSD ?? "n/a"}`,
    `- Highest-cost feature: ${payload.summary.highestCostFeature ?? "n/a"}`,
    `- Failed/refunded calls: ${payload.summary.failedOrRefundedCalls}`,
    `- Duplicate idempotency calls blocked: ${payload.summary.duplicateIdempotencyCallsBlocked}`,
    `- Privacy leak test: ${payload.summary.privacyLeakTestResult.passed === null ? "not run" : payload.summary.privacyLeakTestResult.passed ? "passed" : "failed"}`,
    "",
    "## Entries",
    "",
  ];

  for (const entry of payload.entries) {
    lines.push(
      `### ${entry.feature} ${entry.status}`,
      "",
      `- User hash: ${entry.testUserIDHash}`,
      `- Plan/status: ${entry.plan}/${entry.subscriptionStatus}`,
      `- Credits: before ${entry.creditsBefore}, reserved ${entry.creditsReserved}, charged ${entry.creditsCharged}, after ${entry.creditsAfter}`,
      `- Provider/model: ${entry.provider}/${entry.model}`,
      `- Tokens: input ${entry.inputTokens ?? "null"}, output ${entry.outputTokens ?? "null"}`,
      `- Cost USD: estimated ${entry.estimatedCostUSD ?? "null"}, actual ${entry.actualCostUSD ?? "null"}`,
      `- Cost null reason: ${entry.costNullReason ?? "n/a"}`,
      `- Latency ms: ${entry.latencyMs}`,
      `- Ledger ID: ${entry.ledgerID}`,
      `- Truncation: ${JSON.stringify(entry.truncationMetadata)}`,
      `- Margin estimate: ${JSON.stringify(entry.marginEstimate)}`,
      "",
    );
  }

  return `${lines.join("\n")}\n`;
}

report = new UsageReport(runID);
