import { z } from "zod";
import { MAX_TOKENS, runExtraction, type AttemptResult, type ExtractImage, type ExtractOptions, type Extractor, type TokenUsage } from "./extract.ts";
import { SYSTEM_PROMPT, userInstruction } from "./prompt.ts";
import { buildModelOutputJSONSchema } from "./schema.ts";

/**
 * Google's Gemini over the REST API, for the eval only (docs/DECISIONS.md, 2026-10-02): the Worker still extracts
 * with Anthropic. Plain `fetch` rather than `@google/genai`, so comparing a provider costs no dependency. Field
 * names follow `googleapis/js-genai` `src/types.ts` (`responseJsonSchema`, `mediaResolution`, `thinkingLevel`).
 */
const ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models";
const TIMEOUT_MS = 120_000;
/** Retries on 429/5xx and network failures, like the Anthropic SDK's `maxRetries: 2`. */
const MAX_RETRIES = 2;
const RETRYABLE = new Set([429, 500, 502, 503, 504]);

export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;
export type SleepFn = (ms: number) => Promise<void>;

/** Gemini 3 thinks at a level rather than a budget; Anthropic's two top levels have no Gemini counterpart. */
const THINKING_LEVEL: Record<NonNullable<ExtractOptions["effort"]>, "LOW" | "MEDIUM" | "HIGH"> = {
  low: "LOW",
  medium: "MEDIUM",
  high: "HIGH",
  xhigh: "HIGH",
  max: "HIGH",
};

export function buildGeminiRequest(images: ExtractImage[], options: Pick<ExtractOptions, "effort">): Record<string, unknown> {
  return {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [
      {
        role: "user",
        parts: [
          ...images.map((image) => ({ inlineData: { mimeType: image.mediaType, data: image.data } })),
          { text: userInstruction(images.length) },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: "application/json",
      responseJsonSchema: buildModelOutputJSONSchema(),
      // 1,120 tokens a page; the cheaper levels shrink the page and small print is the whole job.
      mediaResolution: "MEDIA_RESOLUTION_HIGH",
      maxOutputTokens: MAX_TOKENS,
      // Omitted unless asked for: older Gemini models take a thinking budget and refuse a level.
      ...(options.effort ? { thinkingConfig: { thinkingLevel: THINKING_LEVEL[options.effort] } } : {}),
    },
  };
}

const GeminiResponseSchema = z.object({
  candidates: z
    .array(
      z.object({
        content: z.object({ parts: z.array(z.object({ text: z.string().optional(), thought: z.boolean().optional() })).optional() }).optional(),
        finishReason: z.string().optional(),
      }),
    )
    .optional(),
  promptFeedback: z.object({ blockReason: z.string().optional() }).optional(),
  usageMetadata: z
    .object({
      promptTokenCount: z.number().optional(),
      candidatesTokenCount: z.number().optional(),
      thoughtsTokenCount: z.number().optional(),
      cachedContentTokenCount: z.number().optional(),
    })
    .optional(),
});

/** Gemini's prompt count includes the cached part and its candidate count excludes thinking, which is billed as output. */
function usageFrom(metadata: z.infer<typeof GeminiResponseSchema>["usageMetadata"]): TokenUsage {
  const cached = metadata?.cachedContentTokenCount ?? 0;
  return {
    inputTokens: Math.max(0, (metadata?.promptTokenCount ?? 0) - cached),
    outputTokens: (metadata?.candidatesTokenCount ?? 0) + (metadata?.thoughtsTokenCount ?? 0),
    cacheCreationInputTokens: 0,
    cacheReadInputTokens: cached,
  };
}

async function errorDetail(response: Response): Promise<string> {
  const body = await response.text().catch(() => "");
  try {
    const message = (JSON.parse(body) as { error?: { message?: unknown } }).error?.message;
    if (typeof message === "string") return message;
  } catch {
    // Not JSON; fall through to the status line.
  }
  return `HTTP ${response.status}`;
}

export function extractWithGeminiFetch(fetchFn: FetchFn, sleep: SleepFn = (ms) => new Promise((r) => setTimeout(r, ms))): Extractor {
  return (images, options) => {
    const body = JSON.stringify(buildGeminiRequest(images, options));

    const call = async (model: string): Promise<AttemptResult> => {
      for (let retry = 0; ; retry += 1) {
        let response: Response;
        try {
          response = await fetchFn(`${ENDPOINT}/${encodeURIComponent(model)}:generateContent`, {
            method: "POST",
            headers: { "content-type": "application/json", "x-goog-api-key": options.apiKey },
            body,
            signal: AbortSignal.timeout(TIMEOUT_MS),
          });
        } catch (error) {
          if (retry < MAX_RETRIES) {
            await sleep(1000 * 2 ** retry);
            continue;
          }
          return { kind: "upstream", status: null, detail: error instanceof Error ? error.message : String(error) };
        }
        if (!response.ok) {
          if (RETRYABLE.has(response.status) && retry < MAX_RETRIES) {
            await sleep(1000 * 2 ** retry);
            continue;
          }
          return { kind: "upstream", status: response.status, detail: await errorDetail(response) };
        }

        const parsed = GeminiResponseSchema.safeParse(await response.json().catch(() => null));
        if (!parsed.success) {
          return { kind: "reply", usage: usageFrom(undefined), text: null, problem: "unrecognised response envelope" };
        }
        const usage = usageFrom(parsed.data.usageMetadata);
        const blocked = parsed.data.promptFeedback?.blockReason;
        if (blocked) return { kind: "reply", usage, text: null, problem: `blockReason ${blocked}` };

        const candidate = parsed.data.candidates?.[0];
        const finish = candidate?.finishReason;
        if (finish && finish !== "STOP") return { kind: "reply", usage, text: null, problem: `finishReason ${finish}` };
        const parts = (candidate?.content?.parts ?? []).filter((p) => !p.thought && typeof p.text === "string");
        return { kind: "reply", usage, text: parts.length ? parts.map((p) => p.text).join("") : null, problem: null };
      }
    };

    return runExtraction(options, call);
  };
}

/** `fetch` is wrapped rather than passed, because Workers refuse a detached `fetch` ("Illegal invocation"). */
export const extractWithGemini: Extractor = extractWithGeminiFetch((input, init) => fetch(input, init));
