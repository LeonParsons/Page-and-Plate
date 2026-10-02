import { describe, expect, it, vi } from "vitest";
import { MAX_TOKENS } from "../src/extract.ts";
import { buildGeminiRequest, extractWithGeminiFetch, type FetchFn } from "../src/extract-gemini.ts";
import { SYSTEM_PROMPT } from "../src/prompt.ts";
import fixture from "../../fixtures/expected/chickpea-arrabbiata.json";

const okOutput = { status: "ok", recipe: fixture.recipe, warnings: [], reason: null };
const images = [
  { mediaType: "image/jpeg" as const, data: "AAAA" },
  { mediaType: "image/png" as const, data: "BBBB" },
];
const options = { apiKeys: { google: "g-key" }, model: "gemini-3.1-flash-lite" };
const metadata = { promptTokenCount: 3000, candidatesTokenCount: 500, thoughtsTokenCount: 200, cachedContentTokenCount: 1000 };

function reply(output: unknown, overrides: Record<string, unknown> = {}, parts?: unknown[]) {
  const text = typeof output === "string" ? output : JSON.stringify(output);
  const body = { candidates: [{ content: { role: "model", parts: parts ?? [{ text }] }, finishReason: "STOP" }], usageMetadata: metadata, ...overrides };
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

const failure = (status: number, message: string) => new Response(JSON.stringify({ error: { code: status, message, status: "X" } }), { status });

function fake(...steps: Array<() => Promise<Response>>) {
  const fetchFn = vi.fn<FetchFn>();
  for (const step of steps) fetchFn.mockImplementationOnce(step);
  const sleep = vi.fn(async (_ms: number) => {});
  return { extract: extractWithGeminiFetch(fetchFn, sleep), fetchFn, sleep };
}

describe("buildGeminiRequest", () => {
  it("sends the prompt, the pages in order, then the instruction, constrained to the output schema", () => {
    const req = buildGeminiRequest(images, {}) as any;
    expect(req.systemInstruction).toEqual({ parts: [{ text: SYSTEM_PROMPT }] });
    expect(req.contents).toEqual([
      {
        role: "user",
        parts: [
          { inlineData: { mimeType: "image/jpeg", data: "AAAA" } },
          { inlineData: { mimeType: "image/png", data: "BBBB" } },
          { text: "Extract the ingredient list and yield from these 2 consecutive pages of one recipe." },
        ],
      },
    ]);
    expect(req.generationConfig).toMatchObject({ responseMimeType: "application/json", mediaResolution: "MEDIA_RESOLUTION_HIGH", maxOutputTokens: MAX_TOKENS });
    expect(req.generationConfig.responseJsonSchema.properties.status.enum).toEqual(["ok", "no_recipe_found", "unreadable"]);
    expect("thinkingConfig" in req.generationConfig).toBe(false);
  });

  it("maps effort onto Gemini's thinking levels", () => {
    expect((buildGeminiRequest(images, { effort: "low" }) as any).generationConfig.thinkingConfig).toEqual({ thinkingLevel: "LOW" });
    expect((buildGeminiRequest(images, { effort: "max" }) as any).generationConfig.thinkingConfig).toEqual({ thinkingLevel: "HIGH" });
  });
});

describe("extractWithGeminiFetch", () => {
  it("posts to the model with the key in a header and reads the recipe and usage", async () => {
    const { extract, fetchFn } = fake(async () => reply(okOutput));
    const outcome = await extract(images, options);
    expect(fetchFn).toHaveBeenCalledTimes(1);
    const [url, init] = fetchFn.mock.calls[0]!;
    expect(url).toBe("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent");
    expect((init.headers as Record<string, string>)["x-goog-api-key"]).toBe("g-key");
    expect(url).not.toContain("g-key");
    expect(outcome).toMatchObject({ kind: "ok", model: "gemini-3.1-flash-lite", attempts: 1 });
    if (outcome.kind === "ok") expect(outcome.response.recipe).toEqual(fixture.recipe);
    // The prompt count includes the cached part; thinking is billed as output.
    expect(outcome.usage).toEqual({ inputTokens: 2000, outputTokens: 700, cacheCreationInputTokens: 0, cacheReadInputTokens: 1000 });
  });

  it("ignores thought parts and joins the answer's text parts", async () => {
    const json = JSON.stringify(okOutput);
    const { extract } = fake(async () => reply("", {}, [{ text: "Looking at the page…", thought: true }, { text: json.slice(0, 40) }, { text: json.slice(40) }]));
    expect((await extract(images, options)).kind).toBe("ok");
  });

  it("retries a reply cut off at the token limit, on the fallback model when there is one", async () => {
    const { extract, fetchFn } = fake(
      async () => reply(okOutput, { candidates: [{ content: { parts: [{ text: "{" }] }, finishReason: "MAX_TOKENS" }] }),
      async () => reply(okOutput),
    );
    const outcome = await extract(images, { ...options, fallbackModel: "gemini-3.6-flash" });
    expect(fetchFn.mock.calls.map(([url]) => url.split("/").at(-1))).toEqual(["gemini-3.1-flash-lite:generateContent", "gemini-3.6-flash:generateContent"]);
    expect(outcome).toMatchObject({ kind: "ok", model: "gemini-3.6-flash", attempts: 2 });
    expect(outcome.calls.map((c) => c.model)).toEqual(["gemini-3.1-flash-lite", "gemini-3.6-flash"]);
  });

  it("gives up after two invalid replies, with the reason", async () => {
    const { extract } = fake(async () => reply("{ not json"), async () => reply({ ...okOutput, recipe: null }));
    const outcome = await extract(images, options);
    expect(outcome).toMatchObject({ kind: "invalid_output", attempts: 2 });
    if (outcome.kind === "invalid_output") expect(outcome.detail).toContain("recipe");
  });

  it("treats a blocked prompt or an empty reply as a reply to retry, not an outage", async () => {
    const { extract } = fake(
      async () => reply(okOutput, { candidates: undefined, promptFeedback: { blockReason: "OTHER" } }),
      async () => reply(okOutput, { candidates: [] }),
    );
    const outcome = await extract(images, options);
    expect(outcome).toMatchObject({ kind: "invalid_output", attempts: 2, detail: "no text in the response" });
  });

  it("maps no_recipe_found with its reason", async () => {
    const { extract } = fake(async () => reply({ status: "no_recipe_found", recipe: null, warnings: [], reason: "A photograph" }));
    expect(await extract(images, options)).toMatchObject({ kind: "no_recipe_found", reason: "A photograph" });
  });

  it("retries 429 and 5xx twice with backoff, then reports upstream with Google's message", async () => {
    const { extract, fetchFn, sleep } = fake(
      async () => failure(429, "Resource exhausted"),
      async () => failure(503, "Unavailable"),
      async () => failure(429, "Resource exhausted"),
    );
    const outcome = await extract(images, options);
    expect(fetchFn).toHaveBeenCalledTimes(3);
    expect(sleep.mock.calls.map(([ms]) => ms)).toEqual([1000, 2000]);
    expect(outcome).toMatchObject({ kind: "upstream", status: 429, detail: "Resource exhausted", attempts: 1, calls: [] });
  });

  it("reports a rejected request at once, without retrying", async () => {
    const { extract, fetchFn } = fake(async () => failure(400, "Invalid JSON payload received. Unknown name \"foo\""));
    expect(await extract(images, options)).toMatchObject({ kind: "upstream", status: 400, detail: expect.stringContaining("Unknown name") });
    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  it("retries a network failure, then reports upstream with no status", async () => {
    const down = async (): Promise<Response> => { throw new TypeError("fetch failed"); };
    const { extract, fetchFn } = fake(down, down, down);
    expect(await extract(images, options)).toMatchObject({ kind: "upstream", status: null, detail: "fetch failed" });
    expect(fetchFn).toHaveBeenCalledTimes(3);
  });
});

describe("without a key", () => {
  it("fails upstream without calling Google", async () => {
    const { extract, fetchFn } = fake();
    expect(await extract(images, { apiKeys: { anthropic: "a" }, model: "gemini-3.8-flash" })).toMatchObject({
      kind: "upstream",
      status: null,
      detail: "GEMINI_API_KEY is not set",
    });
    expect(fetchFn).not.toHaveBeenCalled();
  });
});
