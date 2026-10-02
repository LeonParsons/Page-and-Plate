import type { Ingredient, Recipe, RecipeYield } from "../schema.ts";
import type { ModelCall, TokenUsage } from "../extract.ts";

/**
 * Pure scoring for `npm run eval` (SPEC §10 Phase 1): ingredient recall/precision matched on name, quantity and
 * unit exact-match rates over the matched pairs, yield accuracy per page. No I/O, no model calls.
 */

/** Lower-case, NFKC, punctuation → space, collapsed whitespace, naive singular ("tomatoes" → "tomatoe" on both sides). */
export function normaliseName(name: string): string {
  return name
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => (word.length > 3 && word.endsWith("s") ? word.slice(0, -1) : word))
    .join(" ");
}

export type Match = { expectedIndex: number; predictedIndex: number; via: "exact" | "contains" };

export type Matching = {
  matches: Match[];
  /** Expected indices with no predicted partner. */
  missed: number[];
  /** Predicted indices with no expected partner. */
  extra: number[];
};

/** One-to-one, greedy: exact normalised names first, then containment in either direction. */
export function matchIngredients(expected: Ingredient[], predicted: Ingredient[]): Matching {
  const exp = expected.map((i) => normaliseName(i.name));
  const pred = predicted.map((i) => normaliseName(i.name));
  const usedPredicted = new Set<number>();
  const matches: Match[] = [];
  const matchedExpected = new Set<number>();

  const pass = (via: Match["via"], accept: (e: string, p: string) => boolean) => {
    exp.forEach((e, ei) => {
      if (matchedExpected.has(ei)) return;
      const pi = pred.findIndex((p, idx) => !usedPredicted.has(idx) && accept(e, p));
      if (pi === -1) return;
      usedPredicted.add(pi);
      matchedExpected.add(ei);
      matches.push({ expectedIndex: ei, predictedIndex: pi, via });
    });
  };

  pass("exact", (e, p) => e === p);
  pass("contains", (e, p) => e.length > 0 && p.length > 0 && (e.includes(p) || p.includes(e)));

  matches.sort((a, b) => a.expectedIndex - b.expectedIndex);
  return {
    matches,
    missed: exp.map((_, i) => i).filter((i) => !matchedExpected.has(i)),
    extra: pred.map((_, i) => i).filter((i) => !usedPredicted.has(i)),
  };
}

const EPSILON = 1e-6;

function numbersEqual(a: number | null, b: number | null): boolean {
  if (a === null || b === null) return a === b;
  return Math.abs(a - b) < EPSILON;
}

export function quantitiesEqual(a: Ingredient, b: Ingredient): boolean {
  return numbersEqual(a.quantity, b.quantity) && numbersEqual(a.quantityMax, b.quantityMax);
}

export function unitsEqual(a: Ingredient, b: Ingredient): boolean {
  return a.unit === b.unit;
}

export function yieldsEqual(a: RecipeYield, b: RecipeYield): boolean {
  return numbersEqual(a.quantity, b.quantity) && numbersEqual(a.quantityMax, b.quantityMax) && normaliseName(a.unit) === normaliseName(b.unit);
}

export type Mismatch = { expected: string; predicted: string; quantity: boolean; unit: boolean };

export type PageScore = {
  stem: string;
  model: string;
  expectedLines: number;
  predictedLines: number;
  matched: number;
  quantityExact: number;
  unitExact: number;
  bothExact: number;
  yieldCorrect: boolean;
  missed: string[];
  extra: string[];
  mismatches: Mismatch[];
};

function describe(i: Ingredient): string {
  const range = i.quantityMax === null ? "" : `–${i.quantityMax}`;
  const amount = i.quantity === null ? "" : `${i.quantity}${range} ${i.unit ?? ""}`.trim();
  return amount ? `${i.name} [${amount}]` : i.name;
}

export function scorePage(stem: string, model: string, expected: Recipe, predicted: Recipe): PageScore {
  const matching = matchIngredients(expected.ingredients, predicted.ingredients);
  let quantityExact = 0;
  let unitExact = 0;
  let bothExact = 0;
  const mismatches: Mismatch[] = [];
  for (const m of matching.matches) {
    const e = expected.ingredients[m.expectedIndex]!;
    const p = predicted.ingredients[m.predictedIndex]!;
    const q = quantitiesEqual(e, p);
    const u = unitsEqual(e, p);
    if (q) quantityExact += 1;
    if (u) unitExact += 1;
    if (q && u) bothExact += 1;
    else mismatches.push({ expected: describe(e), predicted: describe(p), quantity: q, unit: u });
  }
  return {
    stem,
    model,
    expectedLines: expected.ingredients.length,
    predictedLines: predicted.ingredients.length,
    matched: matching.matches.length,
    quantityExact,
    unitExact,
    bothExact,
    yieldCorrect: yieldsEqual(expected.yield, predicted.yield),
    missed: matching.missed.map((i) => describe(expected.ingredients[i]!)),
    extra: matching.extra.map((i) => describe(predicted.ingredients[i]!)),
    mismatches,
  };
}

/** One page's run. `costUSD` is priced per call (see `costOfCalls`), null when any call's model has no price. */
export type RunStats = { ok: boolean; latencyMs: number; costUSD: number | null } & TokenUsage;

export type ModelSummary = {
  model: string;
  pages: number;
  failedPages: number;
  expectedLines: number;
  predictedLines: number;
  matched: number;
  recall: number;
  precision: number;
  quantityExact: number;
  unitExact: number;
  quantityAndUnitExact: number;
  yieldAccuracy: number;
  meanLatencyMs: number;
  inputTokens: number;
  outputTokens: number;
  cacheCreationInputTokens: number;
  cacheReadInputTokens: number;
  estimatedCostUSD: number | null;
};

/** USD per million tokens. `input` is the uncached rate; cache writes and reads are billed separately. */
export type Price = { input: number; output: number; cacheWrite: number; cacheRead: number };

/** Anthropic's standard multipliers: a 5-minute cache write is 1.25× input, a read 0.1× (Opus 5.5: 0.05×). */
const anthropic = (input: number, output: number, readMultiplier = 0.1): Price => ({ input, output, cacheWrite: input * 1.25, cacheRead: input * readMultiplier });

/**
 * Anthropic rates from platform.claude.com/docs/en/about-claude/pricing (fetched 2026-09-30). Gemini 3.8 Flash and
 * 3.5 Flash-Lite from ai.google.dev/gemini-api/docs/pricing (paid tier, fetched 2026-10-02); the other Gemini rows
 * are third-party figures. **3.8 Flash's rate is introductory: it doubles to $1.50 / $7.50 (cache $0.15) on
 * 2027-01-01.** Change the row then, or every cost the eval prints for it is half the truth. Implicit-cache reads
 * are 0.1× there too.
 * Unknown models get a null cost.
 */
export const PRICING: Record<string, Price> = {
  "claude-opus-5-5": anthropic(4, 20, 0.05),
  "claude-opus-5": anthropic(5, 25),
  "claude-opus-4-8": anthropic(5, 25),
  "claude-opus-4-7": anthropic(5, 25),
  "claude-opus-4-6": anthropic(5, 25),
  "claude-sonnet-5-5": anthropic(2, 10),
  "claude-sonnet-5": anthropic(2, 10),
  "claude-sonnet-4-6": anthropic(3, 15),
  "claude-haiku-4-5": anthropic(1, 5),
  "gemini-3.1-flash-lite": { input: 0.25, output: 1.5, cacheWrite: 0.25, cacheRead: 0.025 },
  "gemini-3.5-flash-lite": { input: 0.3, output: 2.5, cacheWrite: 0.3, cacheRead: 0.03 },
  "gemini-3.6-flash": { input: 0.75, output: 3.75, cacheWrite: 0.75, cacheRead: 0.075 },
  "gemini-3.7-flash": { input: 0.75, output: 3.75, cacheWrite: 0.75, cacheRead: 0.075 },
  "gemini-3.8-flash": { input: 0.75, output: 3.75, cacheWrite: 0.75, cacheRead: 0.075 },
};

/** Prices each call at its own model's rate, so a Sonnet retry behind Haiku costs what Sonnet costs. */
export function costOfCalls(calls: ModelCall[]): number | null {
  let total = 0;
  for (const call of calls) {
    const price = PRICING[call.model];
    if (!price) return null;
    total += costUSD(price, call.usage);
  }
  return total;
}

export function costUSD(price: Price, usage: TokenUsage): number {
  return (
    usage.inputTokens * price.input +
    usage.outputTokens * price.output +
    usage.cacheCreationInputTokens * price.cacheWrite +
    usage.cacheReadInputTokens * price.cacheRead
  ) / 1_000_000;
}

const ratio = (num: number, den: number) => (den === 0 ? 0 : num / den);

/** Micro-averaged over all lines of all pages; a failed page contributes its expected lines and nothing else. */
export function summarise(model: string, scores: PageScore[], runs: RunStats[], failedExpectedLines = 0): ModelSummary {
  const expectedLines = scores.reduce((n, s) => n + s.expectedLines, 0) + failedExpectedLines;
  const predictedLines = scores.reduce((n, s) => n + s.predictedLines, 0);
  const matched = scores.reduce((n, s) => n + s.matched, 0);
  const usage: TokenUsage = {
    inputTokens: runs.reduce((n, r) => n + r.inputTokens, 0),
    outputTokens: runs.reduce((n, r) => n + r.outputTokens, 0),
    cacheCreationInputTokens: runs.reduce((n, r) => n + r.cacheCreationInputTokens, 0),
    cacheReadInputTokens: runs.reduce((n, r) => n + r.cacheReadInputTokens, 0),
  };
  const priced = PRICING[model] !== undefined && runs.every((r) => r.costUSD !== null);
  return {
    model,
    pages: runs.length,
    failedPages: runs.filter((r) => !r.ok).length,
    expectedLines,
    predictedLines,
    matched,
    recall: ratio(matched, expectedLines),
    precision: ratio(matched, predictedLines),
    quantityExact: ratio(scores.reduce((n, s) => n + s.quantityExact, 0), matched),
    unitExact: ratio(scores.reduce((n, s) => n + s.unitExact, 0), matched),
    quantityAndUnitExact: ratio(scores.reduce((n, s) => n + s.bothExact, 0), matched),
    yieldAccuracy: ratio(scores.filter((s) => s.yieldCorrect).length, runs.length),
    meanLatencyMs: ratio(runs.reduce((n, r) => n + r.latencyMs, 0), runs.length),
    ...usage,
    estimatedCostUSD: priced ? runs.reduce((n, r) => n + r.costUSD!, 0) : null,
  };
}
