import { describe, expect, it } from "vitest";
import { PRICING, costOfCalls, matchIngredients, normaliseName, quantitiesEqual, scorePage, summarise, unitsEqual, yieldsEqual } from "../src/eval/metrics.ts";
import type { Ingredient, Recipe } from "../src/schema.ts";

function ing(name: string, quantity: number | null = null, unit: Ingredient["unit"] = null, quantityMax: number | null = null): Ingredient {
  return { rawText: name, section: null, quantity, quantityMax, unit, packageSize: null, name, preparation: null, optional: false, scalable: true, confidence: "high" };
}

const yield4 = { quantity: 4, quantityMax: null, unit: "servings", rawText: "Serves 4" };

describe("normaliseName", () => {
  it("lower-cases, strips punctuation, collapses spaces and singularises", () => {
    expect(normaliseName("Chopped Tomatoes,")).toBe("chopped tomatoe");
    expect(normaliseName("  Skinless,  boneless chicken thighs ")).toBe("skinles boneles chicken thigh");
    expect(normaliseName("Parmesan cheese")).toBe("parmesan cheese");
    expect(normaliseName("eggs")).toBe("egg");
    expect(normaliseName("gas")).toBe("gas");
    expect(normaliseName("chillies")).toBe("chillie");
  });
});

describe("matchIngredients", () => {
  it("matches exactly before falling back to containment, one-to-one", () => {
    const expected = [ing("olive oil"), ing("olive oil"), ing("garlic"), ing("ripe cherry tomatoes")];
    const predicted = [ing("cherry tomatoes"), ing("Olive oil"), ing("garlic cloves"), ing("olive oil")];
    const m = matchIngredients(expected, predicted);
    expect(m.matches).toEqual([
      { expectedIndex: 0, predictedIndex: 1, via: "exact" },
      { expectedIndex: 1, predictedIndex: 3, via: "exact" },
      { expectedIndex: 2, predictedIndex: 2, via: "contains" },
      { expectedIndex: 3, predictedIndex: 0, via: "contains" },
    ]);
    expect(m.missed).toEqual([]);
    expect(m.extra).toEqual([]);
  });

  it("reports misses and extras", () => {
    const m = matchIngredients([ing("salt"), ing("black pepper")], [ing("salt"), ing("olive oil")]);
    expect(m.matches).toHaveLength(1);
    expect(m.missed).toEqual([1]);
    expect(m.extra).toEqual([1]);
  });

  it("does not let one predicted line satisfy two expected lines", () => {
    const m = matchIngredients([ing("olive oil"), ing("olive oil")], [ing("olive oil")]);
    expect(m.matches).toHaveLength(1);
    expect(m.missed).toEqual([1]);
  });
});

describe("equality helpers", () => {
  it("compares quantities null-aware with a tolerance, including ranges", () => {
    expect(quantitiesEqual(ing("a", 1.5, "tsp"), ing("a", 1.5000000001, "tsp"))).toBe(true);
    expect(quantitiesEqual(ing("a", 2, "clove", 3), ing("a", 2, "clove", 3))).toBe(true);
    expect(quantitiesEqual(ing("a", 2, "clove", 3), ing("a", 2, "clove"))).toBe(false);
    expect(quantitiesEqual(ing("a"), ing("a"))).toBe(true);
    expect(quantitiesEqual(ing("a"), ing("a", 1, "each"))).toBe(false);
  });

  it("compares units including null", () => {
    expect(unitsEqual(ing("a", 1, "tin"), ing("a", 1, "tin"))).toBe(true);
    expect(unitsEqual(ing("a", 1, "tin"), ing("a", 1, "each"))).toBe(false);
    expect(unitsEqual(ing("a"), ing("a"))).toBe(true);
  });

  it("compares yields on quantity, max and normalised unit", () => {
    expect(yieldsEqual(yield4, { ...yield4, rawText: null, unit: "Servings" })).toBe(true);
    expect(yieldsEqual(yield4, { ...yield4, quantity: 6 })).toBe(false);
    expect(yieldsEqual({ ...yield4, quantityMax: 6 }, yield4)).toBe(false);
    expect(yieldsEqual({ ...yield4, unit: "muffins" }, { ...yield4, unit: "muffin" })).toBe(true);
  });
});

describe("scorePage and summarise", () => {
  const expected: Recipe = {
    title: "T",
    yield: yield4,
    ingredients: [ing("plain flour", 200, "g"), ing("eggs", 3, "each"), ing("garlic", 2, "clove", 3), ing("salt")],
  };
  const predicted: Recipe = {
    title: "T",
    yield: { ...yield4, rawText: "SERVES 4" },
    ingredients: [ing("plain flour", 200, "g"), ing("eggs", 3, "each"), ing("garlic cloves", 2, "each", 3), ing("olive oil", 1, "tbsp")],
  };

  it("counts matches, exact quantities/units, misses, extras and mismatches", () => {
    const s = scorePage("page", "m", expected, predicted);
    expect(s).toMatchObject({ expectedLines: 4, predictedLines: 4, matched: 3, quantityExact: 3, unitExact: 2, bothExact: 2, yieldCorrect: true });
    expect(s.missed).toEqual(["salt"]);
    expect(s.extra).toEqual(["olive oil [1 tbsp]"]);
    expect(s.mismatches).toEqual([{ expected: "garlic [2–3 clove]", predicted: "garlic cloves [2–3 each]", quantity: true, unit: false }]);
  });

  it("micro-averages over pages and prices tokens per model", () => {
    const s1 = scorePage("a", "claude-sonnet-5", expected, predicted);
    const s2 = scorePage("b", "claude-sonnet-5", expected, expected);
    const tokens = (inputTokens: number, outputTokens: number) => ({ inputTokens, outputTokens, cacheCreationInputTokens: 0, cacheReadInputTokens: 0 });
    const run = (ok: boolean, latencyMs: number, usage: ReturnType<typeof tokens>) => ({ ok, latencyMs, ...usage, costUSD: costOfCalls([{ model: "claude-sonnet-5", usage }]) });
    const runs = [run(true, 1000, tokens(1_000_000, 100_000)), run(true, 3000, tokens(0, 0)), run(false, 500, tokens(0, 0))];
    const summary = summarise("claude-sonnet-5", [s1, s2], runs, 4);
    expect(summary.pages).toBe(3);
    expect(summary.failedPages).toBe(1);
    expect(summary.expectedLines).toBe(12);
    expect(summary.matched).toBe(7);
    expect(summary.recall).toBeCloseTo(7 / 12);
    expect(summary.precision).toBeCloseTo(7 / 8);
    expect(summary.quantityExact).toBeCloseTo(7 / 7);
    expect(summary.unitExact).toBeCloseTo(6 / 7);
    expect(summary.quantityAndUnitExact).toBeCloseTo(6 / 7);
    expect(summary.yieldAccuracy).toBeCloseTo(2 / 3);
    expect(summary.meanLatencyMs).toBeCloseTo(1500);
    expect(summary.estimatedCostUSD).toBeCloseTo(2 + 1);
    expect(summarise("unknown-model", [], [], 0).estimatedCostUSD).toBeNull();
    expect(summarise("claude-sonnet-5", [], [{ ...runs[0]!, costUSD: null }], 0).estimatedCostUSD).toBeNull();
  });
});

describe("costOfCalls", () => {
  const usage = (inputTokens: number, outputTokens: number, write = 0, read = 0) => ({ inputTokens, outputTokens, cacheCreationInputTokens: write, cacheReadInputTokens: read });

  it("bills a cache write at 1.25× and a read at 0.1× of base input", () => {
    expect(costOfCalls([{ model: "claude-sonnet-5", usage: usage(0, 0, 1_000_000, 0) }])).toBeCloseTo(2.5);
    expect(costOfCalls([{ model: "claude-sonnet-5", usage: usage(0, 0, 0, 1_000_000) }])).toBeCloseTo(0.2);
    expect(costOfCalls([{ model: "claude-opus-5-5", usage: usage(0, 0, 0, 1_000_000) }])).toBeCloseTo(0.2);
  });

  it("prices a fallback call at the fallback's own rate", () => {
    const calls = [
      { model: "claude-haiku-4-5", usage: usage(1_000_000, 0) },
      { model: "claude-sonnet-5", usage: usage(1_000_000, 0) },
    ];
    expect(costOfCalls(calls)).toBeCloseTo(1 + 2);
    expect(costOfCalls([])).toBe(0);
  });

  it("is null when any call's model has no price", () => {
    expect(costOfCalls([{ model: "claude-haiku-4-5", usage: usage(1, 1) }, { model: "mystery", usage: usage(1, 1) }])).toBeNull();
    expect(PRICING["gemini-3.1-flash-lite"]).toBeDefined();
  });
});
