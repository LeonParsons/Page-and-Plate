import type { ExtractionResponse } from "./schema.ts";

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
