import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createApp, type Bindings } from "../src/app.ts";
import type { ExtractOutcome, Extractor } from "../src/extract.ts";
import type { AttestedKey } from "../src/attest.ts";
import fixture from "../../fixtures/expected/chickpea-arrabbiata.json";

/**
 * The routes and the rule that makes them worth having: when a request is attested, the trial and the week
 * are counted against the **attested key**, not the `x-device-id` the client chose for itself. Without
 * that, a perfectly valid assertion attached to a fresh UUID still buys a fresh trial.
 *
 * The cryptography is `attest.test.ts`. Here the verifiers are injected, so these stay about routing.
 */

const baseEnv = env as unknown as Bindings;
const testEnv: Bindings = { ...baseEnv, APP_KEY: "test-app-key", ANTHROPIC_API_KEY: "test-anthropic-key", GEMINI_API_KEY: "test-gemini-key" };

const usage = { inputTokens: 1000, outputTokens: 200, cacheCreationInputTokens: 0, cacheReadInputTokens: 0 };
const calls = [{ model: "claude-sonnet-5", usage }];
const okOutcome: ExtractOutcome = { kind: "ok", response: fixture as never, model: "claude-sonnet-5", latencyMs: 1, attempts: 1, usage, calls };
const validBody = JSON.stringify({ images: [{ mediaType: "image/jpeg", data: "AAAA" }] });

/** A key id of its own per test: KV outlives a test, and a shared one would share a spent trial. */
function freshKeyId(): string {
  return `good-${crypto.randomUUID()}`;
}

const verifyAttestation = async (keyId: string): Promise<AttestedKey | "chain"> =>
  keyId.startsWith("good-") ? { keyId, publicKeyPem: "pem", receipt: "receipt", counter: 0 } : "chain";

let counter = 0;
const verifyAssertion = async (assertion: Uint8Array) =>
  new TextDecoder().decode(assertion) === "good" ? { counter: ++counter } : ("signature" as const);

describe("App Attest routes", () => {
  let app: ReturnType<typeof createApp>;
  let extract: ReturnType<typeof vi.fn<Extractor>>;

  beforeEach(() => {
    counter = 0;
    extract = vi.fn<Extractor>(async () => okOutcome);
    app = createApp({ extract, verifyAttestation, verifyAssertion });
  });

  const appKey = { "x-app-key": "test-app-key" };

  async function challenge(env: Bindings = testEnv): Promise<string> {
    const res = await app.request("http://worker/attest/challenge", { method: "POST", headers: appKey }, env);
    return ((await res.json()) as { challenge: string }).challenge;
  }

  async function attest(keyId: string, value: string, env: Bindings = testEnv) {
    return app.request(
      "http://worker/attest",
      {
        method: "POST",
        headers: { ...appKey, "content-type": "application/json" },
        body: JSON.stringify({ keyId, challenge: value, attestation: btoa("anything") }),
      },
      env,
    );
  }

  function scan(opts: { device?: string; key?: string; assertion?: string; challenge?: string; env?: Bindings }) {
    const headers: Record<string, string> = {
      "content-type": "application/json",
      ...appKey,
      "x-device-id": opts.device ?? crypto.randomUUID(),
    };
    if (opts.key) headers["x-attest-key"] = opts.key;
    if (opts.assertion) headers["x-attest-assertion"] = btoa(opts.assertion);
    if (opts.challenge) headers["x-attest-challenge"] = opts.challenge;
    return app.request("http://worker/extract", { method: "POST", headers, body: validBody }, opts.env ?? testEnv);
  }

  describe("challenges", () => {
    it("need the app key", async () => {
      const res = await app.request("http://worker/attest/challenge", { method: "POST" }, testEnv);
      expect(res.status).toBe(401);
    });

    it("are different every time", async () => {
      const values = new Set([await challenge(), await challenge(), await challenge()]);
      expect(values.size).toBe(3);
    });

    it("work once", async () => {
      const value = await challenge();
      const keyId = freshKeyId();
      expect((await attest(keyId, value)).status).toBe(200);
      expect((await attest(keyId, value)).status).toBe(401);
    });

    it("cannot be invented", async () => {
      expect((await attest(freshKeyId(), "a-challenge-nobody-issued")).status).toBe(401);
    });
  });

  describe("attesting", () => {
    it("stores a key the verifier accepts", async () => {
      const keyId = freshKeyId();
      expect((await attest(keyId, await challenge())).status).toBe(200);
      // Proven by the fact it can then be asserted against.
      const res = await scan({ key: keyId, assertion: "good", challenge: await challenge() });
      expect(res.status).toBe(200);
    });

    it("refuses one it does not", async () => {
      const res = await attest("some-other-key", await challenge());
      expect(res.status).toBe(401);
      expect(await res.json()).toMatchObject({ error: "unauthorized" });
    });

    it("wants all three fields", async () => {
      const res = await app.request(
        "http://worker/attest",
        { method: "POST", headers: { ...appKey, "content-type": "application/json" }, body: JSON.stringify({ keyId: freshKeyId() }) },
        testEnv,
      );
      expect(res.status).toBe(400);
    });
  });

  describe("scanning with an assertion", () => {
    let keyId: string;

    beforeEach(async () => {
      keyId = freshKeyId();
      await attest(keyId, await challenge());
    });

    it("is allowed, and the counter moves", async () => {
      expect((await scan({ key: keyId, assertion: "good", challenge: await challenge() })).status).toBe(200);
      expect((await scan({ key: keyId, assertion: "good", challenge: await challenge() })).status).toBe(200);
      expect(counter).toBe(2);
    });

    it("burns the challenge even when the signature is wrong", async () => {
      const value = await challenge();
      await scan({ key: keyId, assertion: "forged", challenge: value });
      // The same challenge again cannot be spent, whatever it carries.
      const res = await scan({ key: keyId, assertion: "good", challenge: value, env: { ...testEnv, REQUIRE_ATTESTATION: "true" } });
      expect(res.status).toBe(401);
    });

    it("is refused for a key that never attested", async () => {
      const required = { ...testEnv, REQUIRE_ATTESTATION: "true" };
      const res = await scan({ key: "a-key-from-nowhere", assertion: "good", challenge: await challenge(), env: required });
      expect(res.status).toBe(401);
    });
  });

  describe("when attestation is required", () => {
    const required: Bindings = { ...testEnv, REQUIRE_ATTESTATION: "true" };

    it("a scan without headers is refused, and costs nothing", async () => {
      const res = await scan({ env: required });
      expect(res.status).toBe(401);
      expect(extract).not.toHaveBeenCalled();
    });

    it("a scan with a good assertion goes through", async () => {
      const keyId = freshKeyId();
      await attest(keyId, await challenge(), required);
      expect((await scan({ key: keyId, assertion: "good", challenge: await challenge(), env: required })).status).toBe(200);
    });
  });

  describe("the quota follows the attested key, not the device id", () => {
    it("so a fresh x-device-id does not buy a fresh trial", async () => {
      const twoScans: Bindings = { ...testEnv, FREE_SCANS: "2", DAILY_LIMIT: "10", REQUIRE_ATTESTATION: "true" };
      const keyId = freshKeyId();
      await attest(keyId, await challenge(), twoScans);

      const withNewDeviceId = async () =>
        scan({ device: crypto.randomUUID(), key: keyId, assertion: "good", challenge: await challenge(), env: twoScans });

      expect((await withNewDeviceId()).status).toBe(200);
      expect((await withNewDeviceId()).status).toBe(200);
      // A third, from a device id never seen before — and the trial is still spent, because the trial was
      // never the device id's to begin with. This is the whole of Phase 8b in one assertion.
      const res = await withNewDeviceId();
      expect(res.status).toBe(402);
      expect(await res.json()).toMatchObject({ error: "free_quota_exhausted" });
    });

    it("and an unattested request still falls back to the device id", async () => {
      const twoScans: Bindings = { ...testEnv, FREE_SCANS: "2", DAILY_LIMIT: "10" };
      const device = crypto.randomUUID();
      expect((await scan({ device, env: twoScans })).status).toBe(200);
      expect((await scan({ device, env: twoScans })).status).toBe(200);
      expect((await scan({ device, env: twoScans })).status).toBe(402);
      expect((await scan({ device: crypto.randomUUID(), env: twoScans })).status).toBe(200);
    });
  });
});
