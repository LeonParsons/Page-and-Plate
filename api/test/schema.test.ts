import { describe, expect, it } from "vitest";
import schemaOnDisk from "../../schema/extraction.schema.json";
import {
  ExtractRequestSchema,
  ExtractionResponseSchema,
  IngredientSchema,
  ModelOutputSchema,
  PackageSizeSchema,
  RecipeSchema,
  RecipeYieldSchema,
  UNITS,
  buildExtractionJSONSchema,
  buildModelOutputJSONSchema,
} from "../src/schema.ts";

// Every hand-checked extraction, keyed by file name. Vite resolves the glob at build time, so this works inside workerd.
const expectedFixtures = import.meta.glob("../../fixtures/expected/*.json", { eager: true, import: "default" }) as Record<string, unknown>;

const baseIngredient = {
  rawText: "2 cloves of garlic",
  section: null,
  quantity: 2,
  quantityMax: null,
  unit: "clove",
  packageSize: null,
  name: "garlic",
  preparation: null,
  optional: false,
  scalable: true,
  confidence: "high",
};

describe("fixtures/expected (contract, Worker side)", () => {
  it("has at least ten pages", () => {
    expect(Object.keys(expectedFixtures).length).toBeGreaterThanOrEqual(10);
  });

  for (const [file, json] of Object.entries(expectedFixtures)) {
    it(`${file.split("/").pop()} validates as an ExtractionResponse`, () => {
      const result = ExtractionResponseSchema.safeParse(json);
      expect(result.success, JSON.stringify(result.error?.issues, null, 2)).toBe(true);
      expect(result.data!.recipe.ingredients.length).toBeGreaterThan(0);
      expect(result.data!.recipe.yield.quantity).not.toBeNull();
    });
  }
});

describe("schema/extraction.schema.json", () => {
  it("matches a fresh export (run `npm run schema` after changing src/schema.ts)", () => {
    expect(schemaOnDisk).toEqual(buildExtractionJSONSchema());
  });

  it("lists the 27 SPEC §5 units, with fl_oz as the only non-identifier value", () => {
    expect(UNITS).toHaveLength(27);
    expect(UNITS).toContain("fl_oz");
    const ingredient = (schemaOnDisk as any).properties.recipe.properties.ingredients.items;
    const unitEnum = ingredient.properties.unit.anyOf.find((v: any) => v.enum)?.enum;
    expect(unitEnum).toEqual([...UNITS]);
    expect(ingredient.required).toEqual([
      "rawText", "section", "quantity", "quantityMax", "unit", "packageSize", "name", "preparation", "optional", "scalable", "confidence",
    ]);
    expect(ingredient.additionalProperties).toBe(false);
  });
});

describe("IngredientSchema refinements", () => {
  it("accepts a plain row and an unquantified row", () => {
    expect(IngredientSchema.safeParse(baseIngredient).success).toBe(true);
    expect(IngredientSchema.safeParse({ ...baseIngredient, rawText: "salt", quantity: null, unit: null, name: "salt" }).success).toBe(true);
  });

  it("rejects a zero quantity", () => {
    expect(IngredientSchema.safeParse({ ...baseIngredient, quantity: 0 }).success).toBe(false);
  });

  it("rejects quantityMax at or below quantity, or without quantity", () => {
    expect(IngredientSchema.safeParse({ ...baseIngredient, quantity: 3, quantityMax: 2 }).success).toBe(false);
    expect(IngredientSchema.safeParse({ ...baseIngredient, quantity: 3, quantityMax: 3 }).success).toBe(false);
    expect(IngredientSchema.safeParse({ ...baseIngredient, quantity: 2, quantityMax: 3 }).success).toBe(true);
    expect(IngredientSchema.safeParse({ ...baseIngredient, quantity: null, unit: null, quantityMax: 3 }).success).toBe(false);
  });

  it("rejects a quantity without a unit", () => {
    expect(IngredientSchema.safeParse({ ...baseIngredient, unit: null }).success).toBe(false);
  });

  it("rejects unknown units and unknown keys", () => {
    expect(IngredientSchema.safeParse({ ...baseIngredient, unit: "rasher" }).success).toBe(false);
    expect(IngredientSchema.safeParse({ ...baseIngredient, id: "abc" }).success).toBe(false);
  });

  it("rejects a missing key (null is required, absence is not)", () => {
    const { section: _omit, ...missingSection } = baseIngredient;
    expect(IngredientSchema.safeParse(missingSection).success).toBe(false);
  });

  it("restricts packageSize to mass or volume units", () => {
    expect(PackageSizeSchema.safeParse({ quantity: 400, unit: "g" }).success).toBe(true);
    expect(PackageSizeSchema.safeParse({ quantity: 400, unit: "ml" }).success).toBe(true);
    expect(PackageSizeSchema.safeParse({ quantity: 1, unit: "each" }).success).toBe(false);
    expect(PackageSizeSchema.safeParse({ quantity: 0, unit: "g" }).success).toBe(false);
  });
});

describe("RecipeSchema title", () => {
  const yieldOK = { quantity: 4, quantityMax: null, unit: "servings", rawText: null };

  it("accepts null when no title is visible, but not an empty string", () => {
    expect(RecipeSchema.safeParse({ title: null, yield: yieldOK, ingredients: [] }).success).toBe(true);
    expect(RecipeSchema.safeParse({ title: "", yield: yieldOK, ingredients: [] }).success).toBe(false);
    expect(RecipeSchema.safeParse({ title: "Toast", yield: yieldOK, ingredients: [] }).success).toBe(true);
  });
});

describe("RecipeYieldSchema", () => {
  it("accepts ranges and rejects inverted ones", () => {
    expect(RecipeYieldSchema.safeParse({ quantity: 4, quantityMax: 6, unit: "servings", rawText: "Serves 4–6" }).success).toBe(true);
    expect(RecipeYieldSchema.safeParse({ quantity: 6, quantityMax: 4, unit: "servings", rawText: null }).success).toBe(false);
    expect(RecipeYieldSchema.safeParse({ quantity: null, quantityMax: 6, unit: "servings", rawText: null }).success).toBe(false);
    expect(RecipeYieldSchema.safeParse({ quantity: null, quantityMax: null, unit: "servings", rawText: null }).success).toBe(true);
  });
});

describe("ModelOutputSchema", () => {
  const recipe = { title: "T", yield: { quantity: 4, quantityMax: null, unit: "servings", rawText: null }, ingredients: [baseIngredient] };

  it("requires a recipe when status is ok", () => {
    expect(ModelOutputSchema.safeParse({ status: "ok", recipe, warnings: [], reason: null }).success).toBe(true);
    expect(ModelOutputSchema.safeParse({ status: "ok", recipe: null, warnings: [], reason: null }).success).toBe(false);
  });

  it("allows a null recipe for the failure statuses", () => {
    expect(ModelOutputSchema.safeParse({ status: "no_recipe_found", recipe: null, warnings: [], reason: "Only a photo" }).success).toBe(true);
    expect(ModelOutputSchema.safeParse({ status: "unreadable", recipe: null, warnings: [], reason: null }).success).toBe(true);
    expect(ModelOutputSchema.safeParse({ status: "maybe", recipe: null, warnings: [], reason: null }).success).toBe(false);
  });
});

describe("ExtractRequestSchema", () => {
  const image = { mediaType: "image/jpeg", data: "AAAA" };

  it("accepts one to three images", () => {
    expect(ExtractRequestSchema.safeParse({ images: [image] }).success).toBe(true);
    expect(ExtractRequestSchema.safeParse({ images: [image, image, image] }).success).toBe(true);
    expect(ExtractRequestSchema.safeParse({ images: [] }).success).toBe(false);
    expect(ExtractRequestSchema.safeParse({ images: [image, image, image, image] }).success).toBe(false);
  });

  it("rejects bad media types, data URIs and non-base64 payloads", () => {
    expect(ExtractRequestSchema.safeParse({ images: [{ ...image, mediaType: "image/heic" }] }).success).toBe(false);
    expect(ExtractRequestSchema.safeParse({ images: [{ ...image, data: "data:image/jpeg;base64,AAAA" }] }).success).toBe(false);
    expect(ExtractRequestSchema.safeParse({ images: [{ ...image, data: "AAA" }] }).success).toBe(false);
    expect(ExtractRequestSchema.safeParse({ images: [{ ...image, data: "" }] }).success).toBe(false);
  });

  it("rejects an image over 5 MB decoded", () => {
    const tooBig = "A".repeat(Math.ceil((5 * 1024 * 1024 * 4) / 3 / 4) * 4 + 4);
    expect(ExtractRequestSchema.safeParse({ images: [{ ...image, data: tooBig }] }).success).toBe(false);
  });
});

describe("buildModelOutputJSONSchema (what the model is constrained by)", () => {
  const schema = buildModelOutputJSONSchema();

  function walk(node: unknown, visit: (n: Record<string, unknown>) => void) {
    if (Array.isArray(node)) return node.forEach((n) => walk(n, visit));
    if (node && typeof node === "object") {
      visit(node as Record<string, unknown>);
      Object.values(node).forEach((v) => walk(v, visit));
    }
  }

  it("keeps enums for status, unit and confidence", () => {
    const props = (schema as any).properties;
    expect(props.status.enum).toEqual(["ok", "no_recipe_found", "unreadable"]);
    const ingredient = props.recipe.anyOf[0].properties.ingredients.items;
    expect(ingredient.properties.unit.anyOf[0].enum).toEqual([...UNITS]);
    expect(ingredient.properties.confidence.enum).toEqual(["high", "low"]);
  });

  it("contains no keywords the grammar rejects, and every object forbids extra keys", () => {
    const banned = ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength", "maxLength", "pattern", "minItems", "maxItems", "$schema"];
    walk(schema, (n) => {
      for (const key of banned) expect(n, key).not.toHaveProperty(key);
      if (n["type"] === "object") expect(n["additionalProperties"]).toBe(false);
    });
  });
});
