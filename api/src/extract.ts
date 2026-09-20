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
  /** Anthropic `output_config.effort`; omitted → the API default (high). */
  effort?: "low" | "medium" | "high" | "xhigh" | "max";
};

export type TokenUsage = {
  inputTokens: number;
  outputTokens: number;
};

type OutcomeBase = {
  model: string;
  latencyMs: number;
  /** Model calls made (1, or 2 after a retry). */
  attempts: number;
  usage: TokenUsage;
};

/** Everything the Worker and the eval need to know about one extraction. Errors are values, not throws. */
export type ExtractOutcome =
  | (OutcomeBase & { kind: "ok"; response: ExtractionResponse })
  | (OutcomeBase & { kind: "no_recipe_found" | "unreadable"; reason: string | null })
  | (OutcomeBase & { kind: "invalid_output"; detail: string })
  | (OutcomeBase & { kind: "upstream"; status: number | null; detail: string });

export type Extractor = (images: ExtractImage[], options: ExtractOptions) => Promise<ExtractOutcome>;

/** The one SDK call the extractor makes, so tests can substitute a fake. */
export type ExtractionClient = {
  messages: { create: (params: Anthropic.MessageCreateParamsNonStreaming) => Promise<Anthropic.Message> };
};

/** Room for the JSON plus adaptive thinking; a 25-line recipe is well under 3k output tokens. */
export const MAX_TOKENS = 8000;
const MAX_ATTEMPTS = 2;

const outputFormat = { type: "json_schema" as const, schema: buildModelOutputJSONSchema() };

export function buildRequest(images: ExtractImage[], options: ExtractOptions): Anthropic.MessageCreateParamsNonStreaming {
  return {
    model: options.model,
    max_tokens: MAX_TOKENS,
    system: SYSTEM_PROMPT,
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
      ...(options.effort ? { effort: options.effort } : {}),
    },
  };
}

/** Validates the model output with Zod; retries once on invalid output; maps everything to an outcome. */
export function extractWithClient(client: ExtractionClient): Extractor {
  return async (images, options) => {
    const startedAt = Date.now();
    const usage: TokenUsage = { inputTokens: 0, outputTokens: 0 };
    let attempts = 0;
    let lastDetail = "";

    const finish = <T extends object>(rest: T) => ({ model: options.model, latencyMs: Date.now() - startedAt, attempts, usage, ...rest });

    while (attempts < MAX_ATTEMPTS) {
      attempts += 1;
      let message: Anthropic.Message;
      try {
        message = await client.messages.create(buildRequest(images, options));
      } catch (error) {
        if (error instanceof Anthropic.APIConnectionError) {
          return finish({ kind: "upstream", status: null, detail: error.message });
        }
        if (error instanceof Anthropic.APIError) {
          return finish({ kind: "upstream", status: error.status ?? null, detail: error.message });
        }
        throw error;
      }

      usage.inputTokens += message.usage?.input_tokens ?? 0;
      usage.outputTokens += message.usage?.output_tokens ?? 0;

      if (message.stop_reason === "max_tokens" || message.stop_reason === "refusal") {
        lastDetail = `stop_reason ${message.stop_reason}`;
        continue;
      }
      const text = message.content.find((block) => block.type === "text")?.text;
      if (text === undefined) {
        lastDetail = "no text block in the response";
        continue;
      }
      let json: unknown;
      try {
        json = JSON.parse(text);
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
  };
}

/** Production extractor: a fresh client per request (no module-level state in Workers). */
export const extractWithAnthropic: Extractor = (images, options) =>
  extractWithClient(new Anthropic({ apiKey: options.apiKey, maxRetries: 2, timeout: 120_000 }))(images, options);
