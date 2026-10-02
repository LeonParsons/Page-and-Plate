import { describe, expect, it, vi } from "vitest";
import type { AttemptResult, ExtractOptions } from "../src/extract.ts";
import { routedExtractor, type AttemptFactory } from "../src/extract-routed.ts";
import { providerOf } from "../src/providers.ts";
import fixture from "../../fixtures/expected/chickpea-arrabbiata.json";

const usage = { inputTokens: 100, outputTokens: 50, cacheCreationInputTokens: 0, cacheReadInputTokens: 0 };
const good: AttemptResult = { kind: "reply", usage, text: JSON.stringify({ status: "ok", recipe: fixture.recipe, warnings: [], reason: null }), problem: null };
const invalid: AttemptResult = { kind: "reply", usage, text: "{ not json", problem: null };
const down: AttemptResult = { kind: "upstream", status: 400, detail: "User location is not supported for the API use." };
const images = [{ mediaType: "image/jpeg" as const, data: "AAAA" }];
const shipped: ExtractOptions = {
  apiKeys: { google: "g", anthropic: "a" },
  model: "gemini-3.8-flash",
  fallbackModel: "claude-sonnet-5",
  effort: "low",
};

/** A provider whose attempts answer from a script, recording which models they were asked for. */
function provider(...results: AttemptResult[]) {
  const attempt = vi.fn(async (_model: string) => results.shift()!);
  const factory = vi.fn<AttemptFactory>(() => attempt);
  return { factory, attempt };
}

describe("providerOf", () => {
  it("sends gemini-* to Google and everything else to Anthropic", () => {
    expect(providerOf("gemini-3.8-flash")).toBe("google");
    expect(providerOf("claude-sonnet-5")).toBe("anthropic");
    expect(providerOf("claude-haiku-4-5")).toBe("anthropic");
  });
});

describe("routedExtractor", () => {
  it("answers from Gemini without ever building the Anthropic side", async () => {
    const google = provider(good);
    const anthropic = provider();
    const outcome = await routedExtractor({ google: google.factory, anthropic: anthropic.factory })(images, shipped);
    expect(outcome).toMatchObject({ kind: "ok", model: "gemini-3.8-flash", attempts: 1 });
    expect(google.factory).toHaveBeenCalledWith(images, shipped);
    expect(anthropic.factory).not.toHaveBeenCalled();
  });

  it("retries an invalid Gemini reply on Claude, and prices each call at its own model", async () => {
    const google = provider(invalid);
    const anthropic = provider(good);
    const outcome = await routedExtractor({ google: google.factory, anthropic: anthropic.factory })(images, shipped);
    expect(google.attempt.mock.calls.map(([m]) => m)).toEqual(["gemini-3.8-flash"]);
    expect(anthropic.attempt.mock.calls.map(([m]) => m)).toEqual(["claude-sonnet-5"]);
    expect(outcome).toMatchObject({ kind: "ok", model: "claude-sonnet-5", attempts: 2, retried: { reason: "invalid_output" } });
    expect(outcome.calls.map((c) => c.model)).toEqual(["gemini-3.8-flash", "claude-sonnet-5"]);
  });

  it("hands the scan to Claude when Google refuses it outright", async () => {
    const google = provider(down);
    const anthropic = provider(good);
    const outcome = await routedExtractor({ google: google.factory, anthropic: anthropic.factory })(images, shipped);
    expect(outcome).toMatchObject({ kind: "ok", model: "claude-sonnet-5", attempts: 2, retried: { reason: "upstream", status: 400 } });
  });

  it("builds a provider's attempts once per extraction, even when both attempts go to it", async () => {
    const anthropic = provider(invalid, good);
    const google = provider();
    const options = { apiKeys: { anthropic: "a" }, model: "claude-haiku-4-5", fallbackModel: "claude-sonnet-5" };
    const outcome = await routedExtractor({ google: google.factory, anthropic: anthropic.factory })(images, options);
    expect(anthropic.factory).toHaveBeenCalledTimes(1);
    expect(anthropic.attempt.mock.calls.map(([m]) => m)).toEqual(["claude-haiku-4-5", "claude-sonnet-5"]);
    expect(google.factory).not.toHaveBeenCalled();
    expect(outcome).toMatchObject({ kind: "ok", model: "claude-sonnet-5" });
  });
});
