import Anthropic from "@anthropic-ai/sdk";
import { SYSTEM_PROMPT, userInstruction } from "./prompt.ts";
import { ModelOutputSchema, buildModelOutputJSONSchema, type ExtractionResponse } from "./schema.ts";

export type ExtractImage = {
  mediaType: "image/jpeg" | "image/png" | "image/webp";
  /** Standard base64, no data: prefix. */
  data: string;
};

export type ExtractOptions = {
  apiKey: string;
  model: string;
  /** The model for the second attempt, after an invalid or cut-off reply. Omitted → `model` again. */
  fallbackModel?: string;
  /** Anthropic `output_config.effort`; omitted → the API default (high). Never sent to Haiku, which rejects it. */
  effort?: "low" | "medium" | "high" | "xhigh" | "max";
};

/** Token counts in the shape every provider is billed in. `inputTokens` excludes cache reads and writes. */
export type TokenUsage = {
  inputTokens: number;
  outputTokens: number;
  cacheCreationInputTokens: number;
  cacheReadInputTokens: number;
};

/** One billed model call. A retry on the fallback is a second call on a different model, priced at its own rate. */
export type ModelCall = { model: string; usage: TokenUsage };

type OutcomeBase = {
  /** The model that made the last attempt, so a fallback's answer is attributed to the fallback. */
  model: string;
  latencyMs: number;
  /** Model calls made (1, or 2 after a retry). */
  attempts: number;
  /** Summed over every call. */
  usage: TokenUsage;
  /** Each call that returned a reply, in order (a call that failed upstream bills nothing and is not listed). */
  calls: ModelCall[];
};

/** Everything the Worker and the eval need to know about one extraction. Errors are values, not throws. */
export type ExtractOutcome =
  | (OutcomeBase & { kind: "ok"; response: ExtractionResponse })
  | (OutcomeBase & { kind: "no_recipe_found" | "unreadable"; reason: string | null })
  | (OutcomeBase & { kind: "invalid_output"; detail: string })
  | (OutcomeBase & { kind: "upstream"; status: number | null; detail: string });

export type Extractor = (images: ExtractImage[], options: ExtractOptions) => Promise<ExtractOutcome>;

/**
 * One provider call, reduced to what the retry loop needs. `problem` is a reply that must not be read
 * (cut off, refused); `text` is null when the reply carried no text at all.
 */
export type AttemptResult =
  | { kind: "upstream"; status: number | null; detail: string }
  | { kind: "reply"; usage: TokenUsage; text: string | null; problem: string | null };

/** Room for the JSON plus adaptive thinking; a 25-line recipe is well under 3k output tokens. */
export const MAX_TOKENS = 8000;
const MAX_ATTEMPTS = 2;

export const emptyUsage = (): TokenUsage => ({ inputTokens: 0, outputTokens: 0, cacheCreationInputTokens: 0, cacheReadInputTokens: 0 });

/**
 * The provider-independent half of an extraction: two attempts at most (the second on `fallbackModel` when set),
 * usage summed across them, and every reply parsed and validated with Zod before anything is returned (rule 4).
 */
export async function runExtraction(options: ExtractOptions, attempt: (model: string) => Promise<AttemptResult>): Promise<ExtractOutcome> {
  const startedAt = Date.now();
  const usage = emptyUsage();
  const calls: ModelCall[] = [];
  let attempts = 0;
  let model = options.model;
  let lastDetail = "";

  const finish = <T extends object>(rest: T) => ({ model, latencyMs: Date.now() - startedAt, attempts, usage, calls, ...rest });

  while (attempts < MAX_ATTEMPTS) {
    model = attempts === 0 ? options.model : (options.fallbackModel ?? options.model);
    attempts += 1;
    const result = await attempt(model);
    if (result.kind === "upstream") {
      return finish({ kind: "upstream", status: result.status, detail: result.detail });
    }

    calls.push({ model, usage: result.usage });
    usage.inputTokens += result.usage.inputTokens;
    usage.outputTokens += result.usage.outputTokens;
    usage.cacheCreationInputTokens += result.usage.cacheCreationInputTokens;
    usage.cacheReadInputTokens += result.usage.cacheReadInputTokens;

    if (result.problem !== null) {
      lastDetail = result.problem;
      continue;
    }
    if (result.text === null) {
      lastDetail = "no text in the response";
      continue;
    }
    let json: unknown;
    try {
      json = JSON.parse(result.text);
    } catch (error) {
      lastDetail = `output is not JSON: ${error instanceof Error ? error.message : String(error)}`;
      continue;
    }
    // Zod enforces what the grammar cannot (positive quantities, range order, unit-with-quantity).
    const parsed = ModelOutputSchema.safeParse(json);
    if (!parsed.success) {
      lastDetail = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).slice(0, 5).join("; ");
      continue;
    }

    const output = parsed.data;
    if (output.status === "ok") {
      return finish({ kind: "ok", response: { recipe: output.recipe!, warnings: output.warnings } });
    }
    return finish({ kind: output.status, reason: output.reason });
  }

  return finish({ kind: "invalid_output", detail: lastDetail });
}

/** The one SDK call the extractor makes, so tests can substitute a fake. */
export type ExtractionClient = {
  messages: { create: (params: Anthropic.MessageCreateParamsNonStreaming) => Promise<Anthropic.Message> };
};

const outputFormat = { type: "json_schema" as const, schema: buildModelOutputJSONSchema() };

/** Haiku 4.5 answers a request carrying `effort` with a 400. */
const acceptsEffort = (model: string) => !model.startsWith("claude-haiku-");

export function buildRequest(images: ExtractImage[], options: ExtractOptions): Anthropic.MessageCreateParamsNonStreaming {
  return {
    model: options.model,
    max_tokens: MAX_TOKENS,
    // The prompt, and the output schema the API injects with it, are byte-identical on every request, so one
    // breakpoint lets every device share a single cache entry. Never put anything per-request in here.
    system: [{ type: "text" as const, text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" as const } }],
    messages: [
      {
        role: "user" as const,
        content: [
          ...images.map((image) => ({
            type: "image" as const,
            source: { type: "base64" as const, media_type: image.mediaType, data: image.data },
          })),
          { type: "text" as const, text: userInstruction(images.length) },
        ],
      },
    ],
    output_config: {
      format: outputFormat,
      ...(options.effort && acceptsEffort(options.model) ? { effort: options.effort } : {}),
    },
  };
}

/** Validates the model output with Zod; retries once on invalid output; maps everything to an outcome. */
export function extractWithClient(client: ExtractionClient): Extractor {
  return (images, options) =>
    runExtraction(options, async (model) => {
      let message: Anthropic.Message;
      try {
        message = await client.messages.create(buildRequest(images, { ...options, model }));
      } catch (error) {
        if (error instanceof Anthropic.APIConnectionError) {
          return { kind: "upstream", status: null, detail: error.message };
        }
        if (error instanceof Anthropic.APIError) {
          return { kind: "upstream", status: error.status ?? null, detail: error.message };
        }
        throw error;
      }
      const usage: TokenUsage = {
        inputTokens: message.usage?.input_tokens ?? 0,
        outputTokens: message.usage?.output_tokens ?? 0,
        cacheCreationInputTokens: message.usage?.cache_creation_input_tokens ?? 0,
        cacheReadInputTokens: message.usage?.cache_read_input_tokens ?? 0,
      };
      if (message.stop_reason === "max_tokens" || message.stop_reason === "refusal") {
        return { kind: "reply", usage, text: null, problem: `stop_reason ${message.stop_reason}` };
      }
      const text = message.content.find((block) => block.type === "text")?.text ?? null;
      return { kind: "reply", usage, text, problem: null };
    });
}

/** Production extractor: a fresh client per request (no module-level state in Workers). */
export const extractWithAnthropic: Extractor = (images, options) =>
  extractWithClient(new Anthropic({ apiKey: options.apiKey, maxRetries: 2, timeout: 120_000 }))(images, options);
