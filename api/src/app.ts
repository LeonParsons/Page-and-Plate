import { Hono } from "hono";
import type { Extractor, ExtractOptions } from "./extract.ts";
import { errorResponse } from "./errors.ts";
import { makeVerifier, type EntitlementVerifier, type RejectionReason } from "./entitlement.ts";
import { makeAssertionVerifier, makeAttestationVerifier, type AssertionVerifier, type AttestationVerifier, type AttestedKey } from "./attest.ts";
import { consumeChallenge, fromBase64, issueChallenge, readAttestedKey, writeAttestedKey } from "./challenge.ts";
import { APPLE_APP_ATTEST_ROOT_PEM } from "./apple-root.ts";
import { checkFreeQuota, checkWeeklyQuota, consumeDailyQuota, recordFreeScan, recordWeeklyScan } from "./quota.ts";
import { KEY_NAMES, providerOf, type Provider, type ProviderKeys } from "./providers.ts";
import { ExtractRequestSchema } from "./schema.ts";

export type Bindings = {
  /** Secret: needed when EXTRACT_MODEL or EXTRACT_FALLBACK_MODEL is a Claude model. */
  ANTHROPIC_API_KEY?: string;
  /** Secret: needed when either model is a `gemini-*` model. A billing-enabled project only (docs/DECISIONS.md). */
  GEMINI_API_KEY?: string;
  /** Secret: the shared key the app sends as x-app-key. */
  APP_KEY: string;
  /** The model for the first attempt; `gemini-*` goes to Google, anything else to Anthropic. */
  EXTRACT_MODEL?: string;
  /**
   * The model for the retry after an invalid or cut-off reply. From the other provider it also takes over when the
   * first one fails outright. Unset → EXTRACT_MODEL again.
   */
  EXTRACT_FALLBACK_MODEL?: string;
  /** Anthropic's effort and Gemini's thinking level, for both attempts. */
  EXTRACT_EFFORT?: string;
  DAILY_LIMIT?: string;
  /** The free trial: successful scans per device, ever (SPEC §9). */
  FREE_SCANS?: string;
  /** The subscription's ceiling: successful scans per device in any rolling WEEKLY_WINDOW_DAYS. Never shown. */
  WEEKLY_SCANS?: string;
  WEEKLY_WINDOW_DAYS?: string;
  MAX_BODY_BYTES?: string;
  /** "true" while the app is in development and TestFlight, where every purchase is Sandbox. */
  ALLOW_SANDBOX_ENTITLEMENTS?: string;
  /** Xcode's local StoreKit certificate authority, so simulator purchases verify (see entitlement.ts). */
  XCODE_ROOT_FINGERPRINT?: string;
  /**
   * "true" refuses any scan without a valid App Attest assertion. It cannot be true until every install has
   * attested, and it can never be true for the Simulator, which has no App Attest at all.
   */
  REQUIRE_ATTESTATION?: string;
  /** "true" expects the `appattestdevelop` aaguid, which is what a development build produces. */
  APPATTEST_DEVELOPMENT?: string;
  QUOTA: KVNamespace;
};

export type AppDeps = {
  extract: Extractor;
  /** Injectable clock for the quota's UTC day. */
  now?: () => Date;
  /** Injectable so the tests can exercise the gate without Apple's certificates. */
  verifyEntitlement?: EntitlementVerifier;
  /** Likewise: the attestation suite proves the checks, these let the routes be tested without them. */
  verifyAttestation?: AttestationVerifier;
  verifyAssertion?: AssertionVerifier;
};

export const DEFAULT_MODEL = "gemini-3.8-flash";
const DEFAULT_DAILY_LIMIT = 30;
const DEFAULT_FREE_SCANS = 7;
const DEFAULT_WEEKLY_SCANS = 25;
const DEFAULT_WEEKLY_WINDOW_DAYS = 7;
const DEFAULT_MAX_BODY_BYTES = 8 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BUNDLE_ID = "com.leonparsons.RecipeBasket";
/** What Apple hashes into an attestation's `rpIdHash`: the team id and the bundle id. */
const APP_ID = "F6VXT39M7H.com.leonparsons.RecipeBasket";
/** The two Unlimited plans, mirrored from `Subscription/Products.swift`. */
const PRODUCT_IDS = [
  "com.leonparsons.RecipeBasket.unlimited.monthly",
  "com.leonparsons.RecipeBasket.unlimited.yearly",
] as const;
const EFFORTS = new Set(["low", "medium", "high", "xhigh", "max"]);

function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const bufA = encoder.encode(a);
  const bufB = encoder.encode(b);
  if (bufA.byteLength !== bufB.byteLength) {
    // Compare against itself so the work done doesn't depend on the mismatch.
    crypto.subtle.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.subtle.timingSafeEqual(bufA, bufB);
}

function intSetting(value: string | undefined, fallback: number): number {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/** The extraction settings, with the key of every provider they can reach and the names of any that are missing. */
function extractConfig(env: Bindings): { options: ExtractOptions; missingKeys: string[] } {
  const model = env.EXTRACT_MODEL || DEFAULT_MODEL;
  const fallbackModel = env.EXTRACT_FALLBACK_MODEL || undefined;
  const secrets: Record<Provider, string | undefined> = { anthropic: env.ANTHROPIC_API_KEY, google: env.GEMINI_API_KEY };
  const apiKeys: ProviderKeys = {};
  const missingKeys: string[] = [];
  for (const provider of new Set([model, ...(fallbackModel ? [fallbackModel] : [])].map(providerOf))) {
    const key = secrets[provider];
    if (key) apiKeys[provider] = key;
    else missingKeys.push(KEY_NAMES[provider]);
  }
  const options: ExtractOptions = { apiKeys, model };
  if (fallbackModel) options.fallbackModel = fallbackModel;
  if (env.EXTRACT_EFFORT && EFFORTS.has(env.EXTRACT_EFFORT)) {
    options.effort = env.EXTRACT_EFFORT as ExtractOptions["effort"];
  }
  return { options, missingKeys };
}

export function createApp(deps: AppDeps) {
  const now = deps.now ?? (() => new Date());
  const app = new Hono<{ Bindings: Bindings }>();

  app.onError((err, c) => {
    console.error(JSON.stringify({ event: "unhandled", message: err.message }));
    return errorResponse(c, "internal");
  });

  app.get("/health", (c) => {
    const { options } = extractConfig(c.env);
    return c.json({ ok: true, model: options.model, ...(options.fallbackModel ? { fallbackModel: options.fallbackModel } : {}) });
  });

  /** A one-time challenge. Everything an attested device signs is signed over one of these. */
  app.post("/attest/challenge", async (c) => {
    if (!c.env.APP_KEY) return errorResponse(c, "server_misconfigured");
    if (!timingSafeEqual(c.req.header("x-app-key") ?? "", c.env.APP_KEY)) {
      return errorResponse(c, "unauthorized");
    }
    return c.json({ challenge: await issueChallenge(c.env.QUOTA) });
  });

  /** Once per install: the device proves its key came from the Secure Enclave, and we keep the public half. */
  app.post("/attest", async (c) => {
    if (!c.env.APP_KEY) return errorResponse(c, "server_misconfigured");
    if (!timingSafeEqual(c.req.header("x-app-key") ?? "", c.env.APP_KEY)) {
      return errorResponse(c, "unauthorized");
    }

    const body = (await c.req.json().catch(() => null)) as { keyId?: string; challenge?: string; attestation?: string } | null;
    const keyId = body?.keyId ?? "";
    const challenge = body?.challenge ?? "";
    const attestation = fromBase64(body?.attestation ?? "");
    if (!keyId || !challenge || !attestation) {
      return errorResponse(c, "bad_request", { message: "keyId, challenge and attestation are required" });
    }

    if (!(await consumeChallenge(c.env.QUOTA, challenge))) {
      return errorResponse(c, "unauthorized", { message: "unknown or spent challenge" });
    }

    const verify =
      deps.verifyAttestation ??
      makeAttestationVerifier({
        appId: APP_ID,
        developmentEnv: c.env.APPATTEST_DEVELOPMENT === "true",
        rootCertificatePem: APPLE_APP_ATTEST_ROOT_PEM,
        now,
      });
    const result = await verify(keyId, new TextEncoder().encode(challenge), attestation);
    if (typeof result === "string") {
      console.log(JSON.stringify({ event: "attest", outcome: "rejected", reason: result }));
      return errorResponse(c, "unauthorized", { message: "attestation rejected" });
    }

    await writeAttestedKey(c.env.QUOTA, result);
    console.log(JSON.stringify({ event: "attest", outcome: "ok", key: keyId.slice(0, 8) }));
    return c.json({ ok: true });
  });

  app.post("/extract", async (c) => {
    const requestId = crypto.randomUUID();
    c.header("x-request-id", requestId);
    const startedAt = Date.now();

    // 1. Shared app key, and a key for every provider the configured models reach.
    const { options, missingKeys } = extractConfig(c.env);
    if (!c.env.APP_KEY || missingKeys.length) {
      console.error(JSON.stringify({ event: "misconfigured", missing: [...(c.env.APP_KEY ? [] : ["APP_KEY"]), ...missingKeys] }));
      return errorResponse(c, "server_misconfigured");
    }
    const appKey = c.req.header("x-app-key") ?? "";
    if (!timingSafeEqual(appKey, c.env.APP_KEY)) {
      return errorResponse(c, "unauthorized");
    }

    // 2. Device id (the quota key).
    const deviceId = c.req.header("x-device-id") ?? "";
    if (!UUID.test(deviceId)) {
      return errorResponse(c, "bad_request", { message: "x-device-id must be a UUID" });
    }
    const device = deviceId.toLowerCase();

    // 3. Body size, before and after reading.
    const maxBodyBytes = intSetting(c.env.MAX_BODY_BYTES, DEFAULT_MAX_BODY_BYTES);
    const declared = Number.parseInt(c.req.header("content-length") ?? "", 10);
    if (Number.isFinite(declared) && declared > maxBodyBytes) {
      return errorResponse(c, "payload_too_large", { maxBodyBytes });
    }
    const bodyText = await c.req.text();
    if (new TextEncoder().encode(bodyText).byteLength > maxBodyBytes) {
      return errorResponse(c, "payload_too_large", { maxBodyBytes });
    }

    // 3b. App Attest. The assertion signs SHA-256(challenge ‖ body), so it belongs to this request and no
    // other, and the Secure Enclave's counter stops the same one arriving twice. A device that cannot
    // attest — the Simulator, an Apple silicon Mac — simply sends nothing, which is refused only when
    // REQUIRE_ATTESTATION says so.
    const attestKeyId = c.req.header("x-attest-key") ?? "";
    const assertionHeader = c.req.header("x-attest-assertion") ?? "";
    const challengeHeader = c.req.header("x-attest-challenge") ?? "";
    let attested: AttestedKey | null = null;
    let attestationRejected: string | undefined;

    if (attestKeyId && assertionHeader && challengeHeader) {
      attestationRejected = await (async (): Promise<string | undefined> => {
        const assertion = fromBase64(assertionHeader);
        if (!assertion) return "malformed";
        // Spent whether or not what follows succeeds: a challenge is worth exactly one attempt.
        if (!(await consumeChallenge(c.env.QUOTA, challengeHeader))) return "challenge";

        const stored = await readAttestedKey(c.env.QUOTA, attestKeyId);
        if (!stored) return "unknown_key";

        const clientDataHash = new Uint8Array(
          await crypto.subtle.digest(
            "SHA-256",
            new TextEncoder().encode(challengeHeader + bodyText) as BufferSource,
          ),
        );
        const verify = deps.verifyAssertion ?? makeAssertionVerifier({ appId: APP_ID });
        const result = await verify(assertion, clientDataHash, stored);
        if (typeof result === "string") return result;

        await writeAttestedKey(c.env.QUOTA, { ...stored, counter: result.counter });
        attested = { ...stored, counter: result.counter };
        return undefined;
      })();
    }

    if (c.env.REQUIRE_ATTESTATION === "true" && !attested) {
      console.log(
        JSON.stringify({ event: "extract", requestId, outcome: "unattested", reason: attestationRejected ?? "absent" }),
      );
      return errorResponse(c, "unattested", { message: "this build must attest before it can scan" });
    }

    // The whole point of the phase: what the trial and the week are counted against. An attested key comes
    // from the Secure Enclave and cannot be invented, where `x-device-id` is whatever the client says.
    const identity = attested ? (attested as AttestedKey).keyId.toLowerCase() : device;

    // 4. Shape.
    let bodyJSON: unknown;
    try {
      bodyJSON = JSON.parse(bodyText);
    } catch {
      return errorResponse(c, "bad_request", { message: "body must be JSON" });
    }
    const parsed = ExtractRequestSchema.safeParse(bodyJSON);
    if (!parsed.success) {
      const issues = parsed.error.issues.slice(0, 5).map((i) => ({ path: i.path.join("."), message: i.message }));
      return errorResponse(c, "bad_request", { message: "invalid request", issues });
    }

    // 5. Daily quota — counted before the model call so failures still cost an attempt.
    const limit = intSetting(c.env.DAILY_LIMIT, DEFAULT_DAILY_LIMIT);
    const quota = await consumeDailyQuota(c.env.QUOTA, identity, limit, now());
    if (!quota.allowed) {
      c.header("Retry-After", String(quota.retryAfterSeconds));
      return errorResponse(c, "rate_limited", { limit, retryAfterSeconds: quota.retryAfterSeconds });
    }

    // 6. The scan gate, in two halves. Without a subscription Apple actually sold it is the free trial — a
    // lifetime count, so there is nothing to wait for. With one it is the week's ceiling, which the response
    // reports only as a time, never as a number: the subscription promises enough for a week's cooking, and
    // naming the figure invites counting against it (SPEC §9).
    //
    // A header that fails to verify is simply not a subscription; it falls to the trial rather than earning
    // its own error, so a patched client learns nothing about what it got wrong.
    const header = c.req.header("x-entitlement") ?? "";
    let rejection: RejectionReason | undefined;
    const verify =
      deps.verifyEntitlement ??
      makeVerifier({
        bundleId: BUNDLE_ID,
        productIds: PRODUCT_IDS,
        allowSandbox: c.env.ALLOW_SANDBOX_ENTITLEMENTS === "true",
        rootFingerprint: c.env.XCODE_ROOT_FINGERPRINT,
        // A purchase through Xcode's local StoreKit configuration is in the "Xcode" environment. Tied to
        // the fingerprint override so it can only ever be on in development.
        allowXcodeEnvironment: c.env.XCODE_ROOT_FINGERPRINT !== undefined,
        now,
        onReject: (reason) => {
          rejection = reason;
        },
      });
    const entitled = header !== "" && (await verify(header)) !== null;
    const freeScans = intSetting(c.env.FREE_SCANS, DEFAULT_FREE_SCANS);
    const weeklyScans = intSetting(c.env.WEEKLY_SCANS, DEFAULT_WEEKLY_SCANS);
    const weeklyWindowSeconds = intSetting(c.env.WEEKLY_WINDOW_DAYS, DEFAULT_WEEKLY_WINDOW_DAYS) * 24 * 60 * 60;
    if (entitled) {
      const week = await checkWeeklyQuota(c.env.QUOTA, identity, weeklyScans, weeklyWindowSeconds, now());
      if (!week.allowed) {
        c.header("Retry-After", String(week.retryAfterSeconds));
        return errorResponse(c, "weekly_quota_exhausted", { retryAfterSeconds: week.retryAfterSeconds });
      }
    } else {
      const free = await checkFreeQuota(c.env.QUOTA, identity, freeScans);
      if (!free.allowed) {
        return errorResponse(c, "free_quota_exhausted", { limit: freeScans });
      }
    }

    // 7. Extract.
    const outcome = await deps.extract(parsed.data.images, options);
    if (outcome.kind === "ok") {
      // The week is recorded either way, so subscribing mid-week starts from the true count.
      await recordWeeklyScan(c.env.QUOTA, identity, weeklyWindowSeconds, now());
      if (!entitled) await recordFreeScan(c.env.QUOTA, identity);
    }

    // One structured line per request; never the images or the raw model text.
    console.log(
      JSON.stringify({
        event: "extract",
        requestId,
        device: deviceId.slice(0, 8),
        images: parsed.data.images.length,
        model: outcome.model,
        outcome: outcome.kind,
        attempts: outcome.attempts,
        // Why the fallback ran, as a reason and a status: how often Gemini hands a scan to Claude, and whether
        // that is an outage or a bad reply, is the cost to watch.
        ...(outcome.retried ? { retried: outcome.retried } : {}),
        usage: outcome.usage,
        modelLatencyMs: outcome.latencyMs,
        totalLatencyMs: Date.now() - startedAt,
        quotaUsed: quota.used,
        attested: attested !== null,
        ...(attestationRejected ? { attestationRejected } : {}),
        entitled,
        // Only present when a header was sent and refused: a real subscriber failing verification has to be
        // visible in production, not silently demoted to the trial.
        ...(rejection ? { entitlementRejected: rejection } : {}),
      }),
    );

    switch (outcome.kind) {
      case "ok":
        return c.json(outcome.response, 200);
      case "no_recipe_found":
      case "unreadable":
        return errorResponse(c, outcome.kind, outcome.reason ? { message: outcome.reason } : {});
      case "invalid_output":
        return errorResponse(c, "model_invalid_output");
      case "upstream":
        return errorResponse(c, "upstream_unavailable");
    }
  });

  return app;
}
