import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it, vi } from "vitest";
import { MAX_TOKENS, buildRequest, extractWithClient, type ExtractionClient } from "../src/extract.ts";
import { SYSTEM_PROMPT } from "../src/prompt.ts";
import fixture from "../../fixtures/expected/chickpea-arrabbiata.json";

const okOutput = { status: "ok", recipe: fixture.recipe, warnings: ["Check the tin size"], reason: null };
const images = [
  { mediaType: "image/jpeg" as const, data: "AAAA" },
  { mediaType: "image/png" as const, data: "BBBB" },
  { mediaType: "image/webp" as const, data: "CCCC" },
];
const options = { apiKey: "k", model: "claude-sonnet-5" as const };

function message(output: unknown, overrides: Record<string, unknown> = {}) {
  return {
    id: "msg_1",
    type: "message",
    role: "assistant",
    model: "claude-sonnet-5",
    content: [{ type: "text", text: typeof output === "string" ? output : JSON.stringify(output) }],
    stop_reason: "end_turn",
    stop_sequence: null,
    usage: { input_tokens: 1000, output_tokens: 300 },
    ...overrides,
  };
}

function fakeClient(...steps: Array<() => Promise<unknown>>) {
  const parse = vi.fn();
  for (const step of steps) parse.mockImplementationOnce(step);
  const client = { messages: { create: parse } } as unknown as ExtractionClient;
  return { client, parse };
}

describe("buildRequest", () => {
  it("sends the images in order, then the instruction, with the structured output format", () => {
    const req = buildRequest(images, { ...options, effort: "medium" });
    expect(req.model).toBe("claude-sonnet-5");
    expect(req.max_tokens).toBe(MAX_TOKENS);
    expect(req.system).toBe(SYSTEM_PROMPT);
    expect(req.messages).toHaveLength(1);
    const content = req.messages[0]!.content as Anthropic.ContentBlockParam[];
    expect(content.slice(0, 3).map((c) => (c.type === "image" && c.source.type === "base64" ? [c.source.media_type, c.source.data] : null))).toEqual([
      ["image/jpeg", "AAAA"], ["image/png", "BBBB"], ["image/webp", "CCCC"],
    ]);
    expect(content[3]).toEqual({ type: "text", text: "Extract the ingredient list and yield from these 3 consecutive pages of one recipe." });
    expect(req.output_config!.format!.type).toBe("json_schema");
    expect((req.output_config!.format!.schema as any).properties.status.enum).toEqual(["ok", "no_recipe_found", "unreadable"]);
    expect(req.output_config!.effort).toBe("medium");
  });

  it("omits effort when not configured and words the single-page instruction", () => {
    const req = buildRequest([images[0]!], options);
    expect("effort" in req.output_config!).toBe(false);
    expect((req.messages[0]!.content as Anthropic.ContentBlockParam[])[1]).toEqual({ type: "text", text: "Extract the ingredient list and yield from this cookbook page." });
  });
});

describe("extractWithClient", () => {
  it("returns ok with the recipe, warnings, usage and latency after one call", async () => {
    const { client, parse } = fakeClient(async () => message(okOutput));
    const outcome = await extractWithClient(client)(images, options);
    expect(parse).toHaveBeenCalledTimes(1);
    expect(outcome.kind).toBe("ok");
    if (outcome.kind !== "ok") return;
    expect(outcome.response).toEqual({ recipe: fixture.recipe, warnings: ["Check the tin size"] });
    expect(outcome.usage).toEqual({ inputTokens: 1000, outputTokens: 300 });
    expect(outcome.attempts).toBe(1);
    expect(outcome.model).toBe("claude-sonnet-5");
    expect(outcome.latencyMs).toBeGreaterThanOrEqual(0);
  });

  it("retries once when the output is not JSON, then succeeds", async () => {
    const { client, parse } = fakeClient(
      async () => message("{ not json"),
      async () => message(okOutput),
    );
    const outcome = await extractWithClient(client)(images, options);
    expect(parse).toHaveBeenCalledTimes(2);
    expect(outcome.kind).toBe("ok");
    expect(outcome.attempts).toBe(2);
  });

  it("gives up after two invalid outputs", async () => {
    const { client, parse } = fakeClient(
      async () => message("{ not json"),
      async () => message({ status: "ok", recipe: null, warnings: [], reason: null }),
    );
    const outcome = await extractWithClient(client)(images, options);
    expect(parse).toHaveBeenCalledTimes(2);
    expect(outcome).toMatchObject({ kind: "invalid_output", attempts: 2 });
    if (outcome.kind === "invalid_output") expect(outcome.detail).toContain("recipe");
  });

  it("retries on a missing text block, max_tokens or refusal, accumulating usage", async () => {
    for (const bad of [message(okOutput, { content: [] }), message(okOutput, { stop_reason: "max_tokens" }), message(okOutput, { stop_reason: "refusal" })]) {
      const { client, parse } = fakeClient(async () => bad, async () => message(okOutput));
      const outcome = await extractWithClient(client)(images, options);
      expect(parse).toHaveBeenCalledTimes(2);
      expect(outcome.kind).toBe("ok");
      expect(outcome.usage).toEqual({ inputTokens: 2000, outputTokens: 600 });
    }
  });

  it("validates the output against the schema refinements", async () => {
    const broken = { ...okOutput, recipe: { ...fixture.recipe, ingredients: [{ ...fixture.recipe.ingredients[0]!, quantity: 0 }] } };
    const { client } = fakeClient(async () => message(broken), async () => message(broken));
    const outcome = await extractWithClient(client)(images, options);
    expect(outcome.kind).toBe("invalid_output");
    if (outcome.kind === "invalid_output") expect(outcome.detail).toContain("quantity");
  });

  it("maps no_recipe_found and unreadable with their reason", async () => {
    const { client: a } = fakeClient(async () => message({ status: "no_recipe_found", recipe: null, warnings: [], reason: "Only a photograph" }));
    expect(await extractWithClient(a)(images, options)).toMatchObject({ kind: "no_recipe_found", reason: "Only a photograph", attempts: 1 });
    const { client: b } = fakeClient(async () => message({ status: "unreadable", recipe: null, warnings: [], reason: null }));
    expect(await extractWithClient(b)(images, options)).toMatchObject({ kind: "unreadable", reason: null });
  });

  it("reports API failures as upstream without retrying", async () => {
    const { client: conn, parse: p1 } = fakeClient(async () => { throw new Anthropic.APIConnectionError({ message: "socket hang up" }); });
    expect(await extractWithClient(conn)(images, options)).toMatchObject({ kind: "upstream", status: null, detail: "socket hang up" });
    expect(p1).toHaveBeenCalledTimes(1);

    const { client: overloaded, parse: p2 } = fakeClient(async () => {
      throw new Anthropic.APIError(529, { type: "overloaded_error" }, "Overloaded", new Headers());
    });
    expect(await extractWithClient(overloaded)(images, options)).toMatchObject({ kind: "upstream", status: 529 });
    expect(p2).toHaveBeenCalledTimes(1);
  });

  it("lets unexpected errors propagate", async () => {
    const { client } = fakeClient(async () => { throw new TypeError("bug"); });
    await expect(extractWithClient(client)(images, options)).rejects.toThrow("bug");
  });
});
