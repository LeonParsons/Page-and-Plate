import { extractWithAnthropic, type Extractor } from "../extract.ts";
import { extractWithGemini } from "../extract-gemini.ts";

/** The eval compares providers; the Worker only ever extracts with Anthropic. */
export type Provider = "anthropic" | "google";

export const providerOf = (model: string): Provider => (model.startsWith("gemini-") ? "google" : "anthropic");

export const extractorFor = (model: string): Extractor => (providerOf(model) === "google" ? extractWithGemini : extractWithAnthropic);
