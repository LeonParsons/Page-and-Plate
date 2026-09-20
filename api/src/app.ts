import { Hono } from "hono";
import type { Extractor, ExtractOptions } from "./extract.ts";
import { errorResponse } from "./errors.ts";
import { consumeDailyQuota } from "./quota.ts";
import { ExtractRequestSchema } from "./schema.ts";

export type Bindings = {
  /** Secret. */
  ANTHROPIC_API_KEY: string;
  /** Secret: the shared key the app sends as x-app-key. */
  APP_KEY: string;
  ANTHROPIC_MODEL?: string;
  ANTHROPIC_EFFORT?: string;
  DAILY_LIMIT?: string;
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
const DEFAULT_MAX_BODY_BYTES = 8 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
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
    const quota = await consumeDailyQuota(c.env.QUOTA, deviceId.toLowerCase(), limit, now());
    if (!quota.allowed) {
      c.header("Retry-After", String(quota.retryAfterSeconds));
      return errorResponse(c, "rate_limited", { limit, retryAfterSeconds: quota.retryAfterSeconds });
    }

    // 6. Extract.
    const options: ExtractOptions = {
      apiKey: c.env.ANTHROPIC_API_KEY,
      model: c.env.ANTHROPIC_MODEL ?? DEFAULT_MODEL,
    };
    if (c.env.ANTHROPIC_EFFORT && EFFORTS.has(c.env.ANTHROPIC_EFFORT)) {
      options.effort = c.env.ANTHROPIC_EFFORT as ExtractOptions["effort"];
    }
    const outcome = await deps.extract(parsed.data.images, options);

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
