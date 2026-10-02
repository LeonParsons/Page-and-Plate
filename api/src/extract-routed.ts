import { anthropicAttemptWithKey, runExtraction, type Attempt, type ExtractImage, type ExtractOptions, type Extractor } from "./extract.ts";
import { geminiAttemptWithKey } from "./extract-gemini.ts";
import { providerOf, type Provider } from "./providers.ts";

/** Builds one provider's attempts for one extraction. */
export type AttemptFactory = (images: ExtractImage[], options: ExtractOptions) => Attempt;

/**
 * Each attempt goes to its own model's provider with that provider's key, so the first attempt can be Gemini and
 * the retry Claude (docs/DECISIONS.md, 2026-10-02). A provider's attempts are only built when one is needed: a scan
 * Gemini answers never constructs an Anthropic client.
 */
export function routedExtractor(factories: Record<Provider, AttemptFactory>): Extractor {
  return (images, options) => {
    const built = new Map<Provider, Attempt>();
    return runExtraction(options, (model) => {
      const provider = providerOf(model);
      let attempt = built.get(provider);
      if (!attempt) {
        attempt = factories[provider](images, options);
        built.set(provider, attempt);
      }
      return attempt(model);
    });
  };
}

/** The Worker's extractor, and the eval's. */
export const extract: Extractor = routedExtractor({ anthropic: anthropicAttemptWithKey, google: geminiAttemptWithKey });
