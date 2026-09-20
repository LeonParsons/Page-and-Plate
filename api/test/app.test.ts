import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createApp, type Bindings } from "../src/app.ts";
import type { ExtractOutcome, Extractor } from "../src/extract.ts";
import fixture from "../../fixtures/expected/chickpea-arrabbiata.json";

const baseEnv = env as unknown as Bindings;
const testEnv: Bindings = { ...baseEnv, APP_KEY: "test-app-key", ANTHROPIC_API_KEY: "test-anthropic-key" };

const usage = { inputTokens: 1000, outputTokens: 200 };
const okOutcome: ExtractOutcome = { kind: "ok", response: fixture as any, model: "claude-sonnet-5", latencyMs: 1234, attempts: 1, usage };

const image = { mediaType: "image/jpeg", data: "AAAA" };
const validBody = JSON.stringify({ images: [image] });

function post(app: ReturnType<typeof createApp>, opts: { key?: string | null; device?: string | null; body?: string; headers?: Record<string, string>; env?: Bindings } = {}) {
  const headers: Record<string, string> = { "content-type": "application/json", ...(opts.headers ?? {}) };
  if (opts.key !== null) headers["x-app-key"] = opts.key ?? "test-app-key";
  if (opts.device !== null) headers["x-device-id"] = opts.device ?? crypto.randomUUID();
  return app.request("http://worker/extract", { method: "POST", headers, body: opts.body ?? validBody }, opts.env ?? testEnv);
}

describe("POST /extract", () => {
  let extract: ReturnType<typeof vi.fn<Extractor>>;
  let app: ReturnType<typeof createApp>;

  beforeEach(() => {
    extract = vi.fn<Extractor>(async () => okOutcome);
    app = createApp({ extract });
  });

  it("returns the extraction with a request id", async () => {
    const res = await post(app);
    expect(res.status).toBe(200);
    expect(res.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
    expect(await res.json()).toEqual(fixture);
    expect(extract).toHaveBeenCalledTimes(1);
    const [images, options] = extract.mock.calls[0]!;
    expect(images).toEqual([image]);
    expect(options).toEqual({ apiKey: "test-anthropic-key", model: "claude-sonnet-5" });
  });

  it("passes the configured model and a valid effort through", async () => {
    await post(app, { env: { ...testEnv, ANTHROPIC_MODEL: "claude-opus-5", ANTHROPIC_EFFORT: "medium" } });
    expect(extract.mock.calls[0]![1]).toEqual({ apiKey: "test-anthropic-key", model: "claude-opus-5", effort: "medium" });
    await post(app, { env: { ...testEnv, ANTHROPIC_EFFORT: "extreme" } });
    expect(extract.mock.calls[1]![1].effort).toBeUndefined();
  });

  it("401 without or with a wrong app key, and never calls the extractor", async () => {
    expect((await post(app, { key: null })).status).toBe(401);
    expect((await post(app, { key: "wrong" })).status).toBe(401);
    expect((await post(app, { key: "test-app-key-but-longer" })).status).toBe(401);
    expect(await (await post(app, { key: "wrong" })).json()).toEqual({ error: "unauthorized" });
    expect(extract).not.toHaveBeenCalled();
  });

  it("500 server_misconfigured when the secrets are missing", async () => {
    expect((await post(app, { env: { ...testEnv, APP_KEY: "" } })).status).toBe(500);
    expect((await post(app, { env: { ...testEnv, ANTHROPIC_API_KEY: "" } })).status).toBe(500);
    expect(extract).not.toHaveBeenCalled();
  });

  it("400 without a UUID device id", async () => {
    expect((await post(app, { device: null })).status).toBe(400);
    const res = await post(app, { device: "phone-1" });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "bad_request", message: "x-device-id must be a UUID" });
    expect(extract).not.toHaveBeenCalled();
  });

  it("413 when Content-Length or the body exceeds MAX_BODY_BYTES", async () => {
    const small = { ...testEnv, MAX_BODY_BYTES: "256" };
    const declared = await post(app, { env: small, headers: { "content-length": "1000000" } });
    expect(declared.status).toBe(413);
    const big = JSON.stringify({ images: [{ mediaType: "image/jpeg", data: "A".repeat(400) }] });
    const actual = await post(app, { env: small, body: big });
    expect(actual.status).toBe(413);
    expect(await actual.json()).toEqual({ error: "payload_too_large", maxBodyBytes: 256 });
    expect(extract).not.toHaveBeenCalled();
  });

  it("400 for malformed JSON and for bodies the schema rejects", async () => {
    expect((await post(app, { body: "{not json" })).status).toBe(400);
    expect((await post(app, { body: JSON.stringify({ images: [] }) })).status).toBe(400);
    expect((await post(app, { body: JSON.stringify({ images: [image, image, image, image] }) })).status).toBe(400);
    expect((await post(app, { body: JSON.stringify({ images: [{ mediaType: "image/gif", data: "AAAA" }] }) })).status).toBe(400);
    const res = await post(app, { body: JSON.stringify({ images: [{ mediaType: "image/jpeg", data: "not base64!" }] }) });
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string; issues: { path: string }[] };
    expect(body.error).toBe("bad_request");
    expect(body.issues[0]!.path).toBe("images.0.data");
    expect(extract).not.toHaveBeenCalled();
  });

  it("429 once a device passes DAILY_LIMIT for the UTC day; other devices unaffected", async () => {
    const limited = { ...testEnv, DAILY_LIMIT: "3" };
    const device = crypto.randomUUID();
    for (let i = 0; i < 3; i++) {
      expect((await post(app, { env: limited, device })).status).toBe(200);
    }
    const res = await post(app, { env: limited, device });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);
    expect(await res.json()).toMatchObject({ error: "rate_limited", limit: 3 });
    expect(extract).toHaveBeenCalledTimes(3);

    expect((await post(app, { env: limited, device: crypto.randomUUID() })).status).toBe(200);
    // Same device, different casing of the UUID → same counter.
    expect((await post(app, { env: limited, device: device.toUpperCase() })).status).toBe(429);
  });

  it("resets at the next UTC day", async () => {
    let clock = new Date("2026-09-20T23:59:30Z");
    app = createApp({ extract, now: () => clock });
    const limited = { ...testEnv, DAILY_LIMIT: "1" };
    const device = crypto.randomUUID();
    expect((await post(app, { env: limited, device })).status).toBe(200);
    expect((await post(app, { env: limited, device })).status).toBe(429);
    clock = new Date("2026-09-21T00:00:10Z");
    expect((await post(app, { env: limited, device })).status).toBe(200);
  });

  it("the default limit from wrangler.jsonc is 30", () => {
    expect(baseEnv.DAILY_LIMIT).toBe("30");
    expect(baseEnv.ANTHROPIC_MODEL).toBe("claude-sonnet-5");
  });

  it("maps the failure outcomes to typed errors", async () => {
    const base = { model: "claude-sonnet-5", latencyMs: 10, attempts: 2, usage };
    const cases: [ExtractOutcome, number, Record<string, unknown>][] = [
      [{ ...base, kind: "no_recipe_found", reason: "Only a photograph" }, 422, { error: "no_recipe_found", message: "Only a photograph" }],
      [{ ...base, kind: "unreadable", reason: null }, 422, { error: "unreadable" }],
      [{ ...base, kind: "invalid_output", detail: "zod" }, 502, { error: "model_invalid_output" }],
      [{ ...base, kind: "upstream", status: 529, detail: "overloaded" }, 503, { error: "upstream_unavailable" }],
    ];
    for (const [outcome, status, body] of cases) {
      extract.mockResolvedValueOnce(outcome);
      const res = await post(app);
      expect(res.status).toBe(status);
      expect(await res.json()).toEqual(body);
    }
  });

  it("500 internal when the extractor throws", async () => {
    extract.mockRejectedValueOnce(new Error("boom"));
    const res = await post(app);
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: "internal" });
  });
});

describe("GET /health", () => {
  it("reports the configured model", async () => {
    const app = createApp({ extract: vi.fn<Extractor>() });
    const res = await app.request("http://worker/health", {}, { ...testEnv, ANTHROPIC_MODEL: "claude-opus-5" });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, model: "claude-opus-5" });
  });
});
