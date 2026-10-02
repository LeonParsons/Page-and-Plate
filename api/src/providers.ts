/** The two model providers. A model's name says which one serves it. */
export type Provider = "anthropic" | "google";

export const providerOf = (model: string): Provider => (model.startsWith("gemini-") ? "google" : "anthropic");

/** One API key per provider; only the providers a request can reach need one. */
export type ProviderKeys = Partial<Record<Provider, string>>;

/** The secret that holds each provider's key, for error messages and the misconfiguration check. */
export const KEY_NAMES: Record<Provider, string> = { anthropic: "ANTHROPIC_API_KEY", google: "GEMINI_API_KEY" };
