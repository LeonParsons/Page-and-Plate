import { z } from "zod";

/**
 * The extraction contract (SPEC §5/§6). This file is the source of truth: `npm run schema` exports
 * `ExtractionResponseSchema` to schema/extraction.schema.json, RecipeCore's Codable models mirror it,
 * and both test suites validate every file in fixtures/expected/ against it.
 *
 * Conventions: every key is always present; "absent" is `null`, never a missing key. `id` is not part of
 * the contract — the app assigns it (docs/DECISIONS.md, Phase 0 §1).
 */

export const UNITS = [
  // mass
  "g", "kg", "oz", "lb",
  // volume
  "ml", "l", "tsp", "tbsp", "cup", "fl_oz", "pint",
  // count
  "each", "clove", "tin", "jar", "packet", "bunch", "sprig", "slice", "sheet", "stick", "bulb", "head",
  // vague
  "pinch", "dash", "handful", "splash",
] as const;

export type Unit = (typeof UNITS)[number];

export const MASS_OR_VOLUME_UNITS: ReadonlySet<Unit> = new Set<Unit>([
  "g", "kg", "oz", "lb", "ml", "l", "tsp", "tbsp", "cup", "fl_oz", "pint",
]);

export const UnitSchema = z.enum(UNITS).describe(
  "Unit exactly as printed in the book, from this closed list. Never convert units. If a count word is not in " +
    "the list (rasher, fillet, stalk, leaf, can…), use \"each\" and keep the word in `name`.",
);

export const ConfidenceSchema = z.enum(["high", "low"]);

export const PackageSizeSchema = z
  .strictObject({
    quantity: z.number().positive(),
    unit: UnitSchema,
  })
  .refine((p) => MASS_OR_VOLUME_UNITS.has(p.unit), {
    message: "packageSize.unit must be a mass or volume unit",
    path: ["unit"],
  })
  .describe('Package size printed with the item: "1 x 400g tin" → { quantity: 400, unit: "g" }. Never scaled.');

export const IngredientSchema = z
  .strictObject({
    rawText: z.string().min(1).describe("The printed ingredient line, verbatim."),
    section: z.string().nullable().describe('Sub-heading the line sits under ("For the curry paste"), else null.'),
    quantity: z.number().positive().nullable().describe("Amount as a decimal (1½ → 1.5). null when unquantified."),
    quantityMax: z.number().positive().nullable().describe('Upper bound of a range ("2–3" → quantity 2, quantityMax 3), else null.'),
    unit: UnitSchema.nullable().describe("null only when quantity is null."),
    packageSize: PackageSizeSchema.nullable(),
    name: z.string().min(1).describe('The ingredient itself, lower case unless a proper noun: "chopped tomatoes", "garlic", "Parmesan cheese".'),
    preparation: z.string().nullable().describe('How it is prepared or used: "finely chopped", "for frying", "to serve". null if none.'),
    optional: z.boolean(),
    scalable: z.boolean().describe('false for usage notes like "for frying", "for greasing", "to serve", "to taste".'),
    confidence: ConfidenceSchema.describe('"low" when the text is blurred, cut off, or the interpretation is uncertain.'),
  })
  .refine((i) => i.quantityMax === null || i.quantity === null || i.quantityMax > i.quantity, {
    message: "quantityMax must be greater than quantity",
    path: ["quantityMax"],
  })
  .refine((i) => i.quantity === null || i.unit !== null, {
    message: "unit is required when quantity is set",
    path: ["unit"],
  })
  .refine((i) => i.quantity !== null || i.quantityMax === null, {
    message: "quantityMax requires quantity",
    path: ["quantityMax"],
  });

export const RecipeYieldSchema = z.strictObject({
  quantity: z.number().positive().nullable().describe('"Serves 4–6" → 4; "Makes 12 muffins" → 12. null if the page states no yield.'),
  quantityMax: z.number().positive().nullable().describe('"Serves 4–6" → 6, else null.'),
  unit: z.string().min(1).describe('"servings" for serves/feeds; otherwise the printed noun: "muffins", "loaves".'),
  rawText: z.string().nullable().describe('The printed yield line, e.g. "SERVES 4", else null.'),
}).refine((y) => y.quantityMax === null || (y.quantity !== null && y.quantityMax > y.quantity), {
  message: "quantityMax must be greater than quantity",
  path: ["quantityMax"],
});

export const RecipeSchema = z.strictObject({
  title: z.string().min(1).describe("The recipe title as printed, in its original capitalisation."),
  yield: RecipeYieldSchema,
  ingredients: z.array(IngredientSchema).describe("Every printed ingredient line, in page order."),
});

/** The 200 body of POST /extract and the exported JSON Schema. */
export const ExtractionResponseSchema = z.strictObject({
  recipe: RecipeSchema,
  warnings: z.array(z.string()).describe("Things the user should check: cut-off lists, sub-recipe references, unreadable areas."),
});

export const EXTRACTION_STATUSES = ["ok", "no_recipe_found", "unreadable"] as const;

/** What the model is asked to produce. Flat rather than a union: structured outputs want an object at the top. */
export const ModelOutputSchema = z
  .strictObject({
    status: z.enum(EXTRACTION_STATUSES).describe(
      '"ok" when an ingredient list was found; "no_recipe_found" when the pages contain no ingredient list; ' +
        '"unreadable" when there is one but it cannot be read reliably.',
    ),
    recipe: RecipeSchema.nullable().describe('The extraction when status is "ok", else null.'),
    warnings: z.array(z.string()),
    reason: z.string().nullable().describe('Short explanation when status is not "ok", else null.'),
  })
  .refine((o) => o.status !== "ok" || o.recipe !== null, {
    message: 'recipe is required when status is "ok"',
    path: ["recipe"],
  });

export const IMAGE_MEDIA_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
export const MAX_IMAGES = 3;
/** The API's own per-image limit for base64 input. */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

export const ExtractRequestSchema = z.strictObject({
  images: z
    .array(
      z.strictObject({
        mediaType: z.enum(IMAGE_MEDIA_TYPES),
        data: z
          .string()
          .min(1)
          .refine((s) => s.length % 4 === 0 && BASE64.test(s), { message: "data must be standard base64 without a data: prefix" })
          .refine((s) => (s.length * 3) / 4 <= MAX_IMAGE_BYTES, { message: `each image must decode to at most ${MAX_IMAGE_BYTES} bytes` }),
      }),
    )
    .min(1)
    .max(MAX_IMAGES),
});

export type Ingredient = z.infer<typeof IngredientSchema>;
export type RecipeYield = z.infer<typeof RecipeYieldSchema>;
export type Recipe = z.infer<typeof RecipeSchema>;
export type ExtractionResponse = z.infer<typeof ExtractionResponseSchema>;
export type ModelOutput = z.infer<typeof ModelOutputSchema>;
export type ExtractRequest = z.infer<typeof ExtractRequestSchema>;

export const EXTRACTION_SCHEMA_ID = "https://recipe-basket.app/schema/extraction.schema.json";

/** Keywords the structured-outputs grammar does not accept; Zod still enforces them client-side. */
const UNSUPPORTED_KEYWORDS = ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength", "maxLength", "pattern", "minItems", "maxItems", "$schema"];

function toStructuredOutputSchema(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(toStructuredOutputSchema);
  if (node === null || typeof node !== "object") return node;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
    if (UNSUPPORTED_KEYWORDS.includes(key)) continue;
    out[key] = key === "enum" || key === "required" ? value : toStructuredOutputSchema(value);
  }
  if (out["type"] === "object") out["additionalProperties"] = false;
  return out;
}

/**
 * The JSON Schema sent to the API as `output_config.format.schema`. Built here rather than with the SDK's
 * `zodOutputFormat`, whose transform drops `enum` into the description — we want the unit list grammar-enforced.
 */
export function buildModelOutputJSONSchema(): Record<string, unknown> {
  return toStructuredOutputSchema(z.toJSONSchema(ModelOutputSchema, { target: "draft-2020-12" })) as Record<string, unknown>;
}

/** JSON Schema (draft 2020-12) for the 200 body — what `npm run schema` writes to schema/extraction.schema.json. */
export function buildExtractionJSONSchema(): Record<string, unknown> {
  const generated = z.toJSONSchema(ExtractionResponseSchema, { target: "draft-2020-12" });
  const { $schema, ...rest } = generated as Record<string, unknown>;
  return {
    $schema: $schema ?? "https://json-schema.org/draft/2020-12/schema",
    $id: EXTRACTION_SCHEMA_ID,
    title: "ExtractionResponse",
    description: "Response body of POST /extract (200). Generated from api/src/schema.ts by `npm run schema` — do not edit by hand.",
    ...rest,
  };
}
