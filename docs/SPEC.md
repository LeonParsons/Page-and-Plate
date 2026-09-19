# Recipe Basket — Product Spec (v0.2 draft)

Working name. Place this file at `docs/SPEC.md`.

## 1. Summary

The user photographs a recipe page from a cookbook. The app extracts the ingredient list and the stated yield ("Serves 4", "Makes 12"), the user confirms or corrects it, and sets how many portions they want. Every quantity scales by the same factor. The user then adds that recipe's ingredients to a list in Apple Reminders, or shares them as text.

Each recipe is exported independently. Exporting a second recipe simply adds more items to the same Reminders list. Duplicate items ("Onion — 1" twice) are acceptable.

## 2. Scope

**MVP goals**
- Native iPhone and iPad app, iOS/iPadOS 17+.
- Capture 1–3 pages per recipe (ingredients often span a page turn).
- Reliable structured extraction with a mandatory review step.
- Deterministic scaling with readable fractions (¼ tin, ¾ tsp).
- Per-recipe export to Apple Reminders, with share-as-text as a fallback.
- Single user, single device, no accounts.

**Non-goals for MVP**
- Android or any non-Apple platform.
- Combining or merging ingredients across recipes.
- De-duplicating, updating or deleting reminders.
- Unit conversion (beyond g→kg and ml→l display promotion) and rounding up to whole purchasable items.
- Storing or displaying method text.
- iCloud sync between devices, nutrition, prices, meal planning, multiple recipes from one photo.

## 3. Core flow

1. **Add recipe:** scan pages with the document camera, or pick existing photos. Up to 3 pages.
2. **Extract:** pages are resized and sent to the API. Show progress; allow cancel.
3. **Review:** page images alongside extracted title, yield and ingredient rows. The user edits, adds or deletes rows, then saves. Low-confidence rows and model warnings are highlighted. Save is blocked until the recipe has a base yield.
4. **Portions:** on the recipe screen, "Recipe serves [4]" (from the book, editable) and "I want [1]" stepper, with the factor shown (×¼). Ingredient quantities update live.
5. **Export:** "Add to Reminders" opens a sheet with every ingredient ticked except staples. The user adjusts ticks, confirms the target list, and taps "Add N items". "Share" sends the same ticked lines as plain text.

## 4. Screens

- **Recipes (home):** list or grid of recipes with thumbnail, title, target portions and "Last added to Reminders" date if any. "Add recipe" button. On iPad, a split view: list on the left, recipe on the right.
- **Capture:** document camera or photo picker, page thumbnails with reorder/delete, "Extract" button.
- **Review / Edit recipe:** title, optional source note ("Book name, p.88"), yield fields, warnings banner, ingredient rows. Each row edits structured fields: quantity, max quantity, unit (picker), package size, name, preparation, optional, scalable. The raw printed text is shown read-only under each row.
- **Recipe detail:** portions stepper, scaled ingredient list grouped by section, "Add to Reminders", "Share", "Edit".
- **Export sheet:** target Reminders list picker (defaults to last used; option to create a list called "Shopping"), ingredient checklist, "Add N items" button, confirmation ("Added 9 items to Shopping").
- **Settings:** default Reminders list, staples list (unticked by default on export).

## 5. Data model

Swift types in `RecipeCore`, mirrored by the Worker's Zod schema.

```swift
enum Unit: String, Codable, CaseIterable {
    // mass
    case g, kg, oz, lb
    // volume
    case ml, l, tsp, tbsp, cup, flOz = "fl_oz", pint
    // count
    case each, clove, tin, jar, packet, bunch, sprig, slice, sheet, stick, bulb, head
    // vague
    case pinch, dash, handful, splash
}

struct PackageSize: Codable, Equatable {
    var quantity: Double
    var unit: Unit               // mass or volume only
}

struct Ingredient: Codable, Equatable, Identifiable {
    var id: UUID
    var rawText: String          // verbatim printed line
    var section: String?         // "For the dressing"
    var quantity: Double?        // nil = unquantified ("salt, to taste")
    var quantityMax: Double?     // ranges: "2–3" → 2 and 3
    var unit: Unit?              // nil only when quantity is nil
    var packageSize: PackageSize? // "1 x 400g tin" → tin, 400 g
    var name: String             // "chopped tomatoes", "garlic", "eggs"
    var preparation: String?     // "finely chopped", "for frying"
    var optional: Bool
    var scalable: Bool           // false for "for frying", "for greasing", "to serve"
    var confidence: Confidence   // .high / .low
}

struct RecipeYield: Codable, Equatable {
    var quantity: Double?        // "Serves 4–6" → 4
    var quantityMax: Double?     // → 6
    var unit: String             // "servings", "muffins"
    var rawText: String?
}
```

**SwiftData `Recipe` model (app target):** id, title, sourceNote, pageImages (downscaled JPEG data, external storage), yield, targetYield (Int ≥ 1, defaults to base yield), ingredients, createdAt, updatedAt, lastExportedAt.

**Settings:** defaultRemindersListID, staples (default: salt, black pepper, olive oil, vegetable oil, water; matched case-insensitively against `name`).

## 6. Extraction API

`POST /extract`

- Headers: `x-app-key` (shared secret), `x-device-id` (random UUID created on first launch, stored in Keychain).
- Body: `{ images: [{ mediaType: "image/jpeg", data: "<base64>" }] }` — 1 to 3 images.
- Responses:
  - `200 { recipe: { title, yield, ingredients }, warnings: string[] }`
  - `401` bad app key · `413` too large · `422 { error: "no_recipe_found" | "unreadable" }` · `429` rate limited · `502 { error: "model_invalid_output" }`

**Implementation**
- Zod schema is the source of truth; `npm run schema` writes `schema/extraction.schema.json`.
- Use the API's structured output / strict tool use if supported for the chosen model; otherwise a single forced tool call (`record_recipe`). Validate with Zod; retry once on failure.
- Don't store images server-side; don't log image data or raw model output.

**Extraction rules for the system prompt**
- Extract ingredients and yield only. Do not transcribe method text.
- `rawText` is the verbatim printed line.
- Never invent ingredients. If the list appears to continue beyond the photo, add a warning.
- Dual units ("200g/7oz") → use the metric value.
- Written and unicode fractions → decimals ("1½" → 1.5).
- Ranges → `quantity` and `quantityMax`.
- Compound quantities ("1 tbsp plus 1 tsp olive oil") → two separate entries. Do not add them up.
- "Salt and pepper" → two unquantified entries.
- "1 x 400g tin chopped tomatoes" → quantity 1, unit `tin`, packageSize 400 g, name "chopped tomatoes".
- "Juice of 1 lemon" → quantity 1, unit `each`, name "lemon", preparation "juiced". "Zest and juice of 1 lemon" is one lemon.
- Usage notes ("for frying", "to serve") go in `preparation`, and set `scalable: false`.
- Sub-recipe references ("1 quantity shortcrust pastry, see p.210") → quantity 1, unit `each`, plus a warning.
- `confidence: "low"` when text is blurred, cut off or the interpretation is uncertain.

## 7. Scaling, rounding and formatting (`RecipeCore`)

**Scaling**
- Base yield = `yield.quantity` (the lower bound of "Serves 4–6").
- Factor = `targetYield / baseYield`.
- When `scalable`, multiply `quantity` and `quantityMax`. Unscalable and unquantified ingredients pass through unchanged.
- Package size never scales ("¼ tin (400 g)", not "1 tin (100 g)").

**Rounding** (applied to scaled values only)
- `g`, `ml`: < 10 → nearest 0.5; 10–100 → nearest 5; 100–1000 → nearest 10; ≥ 1000 → promote to kg/l, 2 dp, trailing zeros trimmed.
- `kg`, `l` as printed: 2 dp, trailing zeros trimmed.
- `tsp`, `tbsp`: nearest of whole + {0, ⅛, ¼, ½, ¾}.
- `cup`, count units, vague units: nearest of whole + {0, ⅛, ¼, ⅓, ½, ⅔, ¾}.
- `oz`: nearest ½. `lb`: nearest ¼. `fl_oz`: nearest ½. `pint`: nearest ¼.
- Ties round up. A non-zero amount never rounds to zero; it floors at the smallest step.
- Unscaled values (factor 1) display exactly as extracted.

**Fraction display:** 0.25 → "¼", 2.5 → "2½", 0.125 → "⅛". Decimals for g/ml/kg/l/oz only.

**Line text** (used for reminder titles and share text)
- `Name — amount unit` with the ingredient name first, capitalised: `Plain flour — 100 g`, `Garlic — 2 cloves`, `Eggs — ¾`, `Chopped tomatoes — ¼ tin (400 g)`.
- Ranges: `Garlic — 4–6 cloves`.
- Unit words pluralise when the amount (or range max) is greater than 1: `1 tin`, `¼ tin`, `1½ tins`. Abbreviated units (g, ml, tsp, tbsp) never pluralise.
- `each` shows no unit word.
- Unquantified: name only, e.g. `Salt`.
- Optional: suffix ` (optional)`.
- Preparation is not included in the line text.

## 8. Export

**Add to Reminders**
- Request full access to reminders on first use with a clear explanation (`NSRemindersFullAccessUsageDescription`). If denied, explain how to enable it in Settings and offer Share instead.
- List picker shows the user's Reminders lists; defaults to the last used; can create "Shopping".
- One reminder per ticked ingredient. Title = line text. Notes = `Recipe title · for N`.
- Always adds new reminders. Never reads back, updates or deletes existing ones. Exporting the same recipe twice creates duplicates; that is accepted.
- On success: confirmation with item count and list name; set `lastExportedAt`.
- Test note: if the chosen list is a Grocery-type list in Reminders, iOS may group items into sections based on the title. Check this on a device in Phase 4; it's one reason the ingredient name leads the title.

**Share**
- `ShareLink` with plain text: first line the recipe title and portions, then one ticked line per row.

## 9. Security, privacy, cost

- The Worker checks `x-app-key`, enforces a per-device rate limit (default 30 extractions/day) and a max body size.
- Set a monthly spend limit in the Anthropic Console.
- The shared app key can be extracted from the app binary. Acceptable for personal and TestFlight use only; replace with real authentication before any public release.
- Page images go only to the Worker and are not stored there. On device, store downscaled page images and extracted data only.

## 10. Phases and acceptance criteria

**Phase 0 — Project scaffold and `RecipeCore`**
- XcodeGen project with app target and test target; local `RecipeCore` package; empty home screen that builds and runs in the simulator.
- `RecipeCore`: models, scaling, rounding, fraction display, line text formatting.
- ✅ Every case in §11 is a fixture in `fixtures/scaling/` and passes under `swift test`. `RecipeCore` imports only Foundation. App builds with no warnings.

**Phase 1 — Extraction API and evals**
- Worker with `/extract`, auth, rate limit, Zod validation, retry, typed errors, schema export.
- Contract test: Worker validates and `RecipeCore` decodes every file in `fixtures/expected/`.
- `npm run eval`: runs each photo in `fixtures/photos/` and reports ingredient recall and precision (matched on name), quantity exact-match rate, unit exact-match rate, yield accuracy, and mean latency per model.
- ✅ Eval runs on ≥ 10 real cookbook pages (≈ 100+ ingredient lines). Initial targets: ≥ 95% ingredient recall, ≥ 90% quantity-and-unit exact match. At this sample size, differences under ~5 percentage points between models or prompt versions are noise.

**Phase 2 — Capture and review**
- Document camera and photo picker, up to 3 pages, resize, upload, loading/cancel/error states, review screen per §4, SwiftData save.
- ✅ Airplane mode shows a clear error and loses nothing. Every field of every row is editable. A recipe without a base yield can't be saved. Recipes and page images survive app restart.

**Phase 3 — Recipes list and portions**
- Home screen, recipe detail with portions stepper and live scaled list, edit and delete recipe, iPad split view.
- ✅ UI shows the same values as the `RecipeCore` fixtures for the same inputs. Target portions persist per recipe.

**Phase 4 — Export**
- Export sheet, Reminders permission flow, list picker, create "Shopping" list, add reminders, share text, settings screen.
- ✅ On a physical iPhone: export a recipe at 1 portion; titles and notes match the formatting rules; staples arrive unticked; exporting again adds duplicates without error; denied permission shows guidance and Share still works. Grocery-list section behaviour noted in `docs/DECISIONS.md`.

**Later (not MVP):** combined shopping list across recipes, iCloud sync between iPhone and iPad (SwiftData + CloudKit), on-device extraction with Apple's Foundation Models framework to remove the API cost, storing method text, public release with real auth.

## 11. Scaling and formatting fixtures (Phase 0)

Each case: ingredient + base yield + target yield → expected line text.

1. "200g/7oz plain flour" (extracted as 200 g), serves 4 → 2 → `Plain flour — 100 g`
2. "1 x 400g tin chopped tomatoes", serves 4 → 1 → `Chopped tomatoes — ¼ tin (400 g)`
3. Same tin, serves 4 → 6 → `Chopped tomatoes — 1½ tins (400 g)`
4. "2–3 garlic cloves, crushed", serves 4 → 8 → `Garlic — 4–6 cloves`
5. "1½ tsp baking powder", serves 4 → 2 → `Baking powder — ¾ tsp`
6. "1 tsp ground cumin", serves 4 → 1 → `Ground cumin — ¼ tsp`
7. "3 eggs", serves 4 → 1 → `Eggs — ¾`
8. "3 eggs", serves 4 → 6 → `Eggs — 4½`
9. "Salt and freshly ground black pepper" → `Salt`, `Black pepper` (both staples, unticked by default)
10. "2 tbsp oil, for frying", serves 4 → 12 → `Oil — 2 tbsp` (unscalable)
11. "A handful of basil leaves", serves 2 → 4 → `Basil leaves — 2 handfuls`
12. "Serves 4–6", target 2 → factor 0.5
13. "Makes 12 muffins", target 18 → factor 1.5
14. "750 g potatoes", serves 2 → 4 → `Potatoes — 1.5 kg`
15. "400 g butter", serves 3 → 1 → 133.3 g → `Butter — 130 g`
16. "1 g saffron", serves 8 → 1 → 0.125 g → `Saffron — 0.5 g` (never zero)
17. "1 tin coconut milk", serves 6 → 2 → `Coconut milk — ⅓ tin`
18. "2–3 tbsp double cream", serves 4 → 1 → `Double cream — ½–¾ tbsp`
19. "1 tbsp plus 1 tsp olive oil" (two entries), serves 2 → 4 → `Olive oil — 2 tbsp`, `Olive oil — 2 tsp`
20. "3 tsp sugar", serves 4 → 3 → 2.25 → `Sugar — 2¼ tsp`
21. "1 bay leaf (optional)", serves 4 → 4 → `Bay leaf — 1 (optional)`
22. "1 quantity shortcrust pastry", serves 4 → 2 → `Shortcrust pastry — ½`
23. Tie rule: "1½ tsp paprika", serves 4 → 1 → 0.375 tsp, halfway between ¼ and ½ → `Paprika — ½ tsp`

## 12. Open questions

1. Personal use and TestFlight only, or eventual App Store release? (Drives authentication, cost controls and a privacy policy.)
2. Should recipes sync between iPhone and iPad from day one, or is that "Later"?
3. Should method text be stored in future? (Affects the data model and the copyright position of keeping book content.)
