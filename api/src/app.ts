import { Hono } from "hono";
import type { Extractor, ExtractOptions } from "./extract.ts";
import { errorResponse } from "./errors.ts";
import { checkFreeQuota, checkWeeklyQuota, consumeDailyQuota, recordFreeScan, recordWeeklyScan } from "./quota.ts";
import { ExtractRequestSchema } from "./schema.ts";

export type Bindings = {
  /** Secret. */
  ANTHROPIC_API_KEY: string;
  /** Secret: the shared key the app sends as x-app-key. */
  APP_KEY: string;
  ANTHROPIC_MODEL?: string;
  ANTHROPIC_EFFORT?: string;
  DAILY_LIMIT?: string;
  /** The free trial: successful scans per device, ever (SPEC §9). */
  FREE_SCANS?: string;
  /** The subscription's ceiling: successful scans per device in any rolling WEEKLY_WINDOW_DAYS. Never shown. */
  WEEKLY_SCANS?: string;
  WEEKLY_WINDOW_DAYS?: string;
  MAX_BODY_BYTES?: string;
  QUOTA: KVNamespace;
};

export type AppDeps = {
  extract: Extractor;
  /** Injectable clock for the quota's UTC day. */
  now?: () => Date;
};

export const DEFAULT_MODEL = "claude-sonnet-5";
const DEFAULT_DAILY_LIMIT = 30;
const DEFAULT_FREE_SCANS = 5;
const DEFAULT_WEEKLY_SCANS = 25;
const DEFAULT_WEEKLY_WINDOW_DAYS = 7;
const DEFAULT_MAX_BODY_BYTES = 8 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** A compact JWS: three base64url segments. The shape the app's signed App Store transaction has. */
const JWS = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
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

export function createApp(deps: AppDeps) {
  const now = deps.now ?? (() => new Date());
  const app = new Hono<{ Bindings: Bindings }>();

  app.onError((err, c) => {
    console.error(JSON.stringify({ event: "unhandled", message: err.message }));
    return errorResponse(c, "internal");
  });

  app.get("/health", (c) => c.json({ ok: true, model: c.env.ANTHROPIC_MODEL ?? DEFAULT_MODEL }));

  app.post("/extract", async (c) => {
    const requestId = crypto.randomUUID();
    c.header("x-request-id", requestId);
    const startedAt = Date.now();

    // 1. Shared app key.
    if (!c.env.APP_KEY || !c.env.ANTHROPIC_API_KEY) {
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
    const device = deviceId.toLowerCase();
    const quota = await consumeDailyQuota(c.env.QUOTA, device, limit, now());
    if (!quota.allowed) {
      c.header("Retry-After", String(quota.retryAfterSeconds));
      return errorResponse(c, "rate_limited", { limit, retryAfterSeconds: quota.retryAfterSeconds });
    }

    // 6. The scan gate, in two halves. Without the app's signed subscription transaction it is the free trial —
    // a lifetime count, so there is nothing to wait for. With one it is the week's ceiling, which the response
    // reports only as a time, never as a number: the subscription promises enough for a week's cooking, and
    // naming the figure invites counting against it (SPEC §9). The JWS is not yet verified here — it is trusted
    // like the app key is — so this holds only until Phase 8 verifies it.
    const entitled = JWS.test(c.req.header("x-entitlement") ?? "");
    const freeScans = intSetting(c.env.FREE_SCANS, DEFAULT_FREE_SCANS);
    const weeklyScans = intSetting(c.env.WEEKLY_SCANS, DEFAULT_WEEKLY_SCANS);
    const weeklyWindowSeconds = intSetting(c.env.WEEKLY_WINDOW_DAYS, DEFAULT_WEEKLY_WINDOW_DAYS) * 24 * 60 * 60;
    if (entitled) {
      const week = await checkWeeklyQuota(c.env.QUOTA, device, weeklyScans, weeklyWindowSeconds, now());
      if (!week.allowed) {
        c.header("Retry-After", String(week.retryAfterSeconds));
        return errorResponse(c, "weekly_quota_exhausted", { retryAfterSeconds: week.retryAfterSeconds });
      }
    } else {
      const free = await checkFreeQuota(c.env.QUOTA, device, freeScans);
      if (!free.allowed) {
        return errorResponse(c, "free_quota_exhausted", { limit: freeScans });
      }
    }

    // 7. Extract.
    const options: ExtractOptions = {
      apiKey: c.env.ANTHROPIC_API_KEY,
      model: c.env.ANTHROPIC_MODEL ?? DEFAULT_MODEL,
    };
    if (c.env.ANTHROPIC_EFFORT && EFFORTS.has(c.env.ANTHROPIC_EFFORT)) {
      options.effort = c.env.ANTHROPIC_EFFORT as ExtractOptions["effort"];
    }
    const outcome = await deps.extract(parsed.data.images, options);
    if (outcome.kind === "ok") {
      // The week is recorded either way, so subscribing mid-week starts from the true count.
      await recordWeeklyScan(c.env.QUOTA, device, weeklyWindowSeconds, now());
      if (!entitled) await recordFreeScan(c.env.QUOTA, device);
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
        usage: outcome.usage,
        modelLatencyMs: outcome.latencyMs,
        totalLatencyMs: Date.now() - startedAt,
        quotaUsed: quota.used,
        entitled,
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
