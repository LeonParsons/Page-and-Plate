# Page & Plate — Product Spec (v0.3 draft)

Named 2026-09-22; the working name was Recipe Basket, which survives as the Xcode target and bundle id.

## 1. Summary

The user photographs a recipe page from a cookbook. The app extracts the ingredient list and the stated yield ("Serves 4", "Makes 12"), the user confirms or corrects it, and sets how many portions they want. Every quantity scales by the same factor. The user then adds that recipe's ingredients to a list in Apple Reminders, or shares them as text.

A **planner** (v0.3) puts recipes on the days of a week, each meal with its own portions, and exports the whole week in one go. Within a week export, lines whose ingredient name, unit and package size match exactly are merged (quantities added, then rounded once); nothing fuzzier is merged. A single recipe can still be exported on its own exactly as before. Exporting again adds more items to the same Reminders list; duplicates are acceptable.

## 2. Scope

**MVP goals**
- Native iPhone and iPad app, iOS/iPadOS 17+.
- Capture 1–3 pages per recipe (ingredients often span a page turn).
- Reliable structured extraction with a mandatory review step.
- Deterministic scaling with readable fractions (¼ tin, ¾ tsp).
- Per-recipe export to Apple Reminders, with share-as-text as a fallback.
- **No accounts of ours.** Identity, where it is needed at all, is the user's own Apple Account. Phase 9 syncs a user's own devices through their iCloud; §10 "Later — a shared week" adds an invited guest the same way. We never hold a user record.

**v0.3 goals (Phases 5–6)**
- A week planner: any number of meals per day, each with its own portions; move, reorder and remove; navigate weeks; add from the library or by scanning straight onto a day.
- One export for a planned week, merging only exact matches (name + unit + package size).

**v0.4 goals (Phase 7)**
- A free tier — 20 scans in any rolling 30 days (a scan is one extraction that returns a recipe; failures don't count) — and an auto-renewable subscription, **Page & Plate Unlimited** (monthly or yearly, price TBC), that lifts it. Star ratings on recipes.

**Non-goals**
- Android or any non-Apple platform.
- Fuzzy merging across recipes (plurals, "red onion" vs "onion", tbsp into ml).
- De-duplicating, updating or deleting reminders.
- Unit conversion (beyond g→kg and ml→l display promotion) and rounding up to whole purchasable items.
- Storing or displaying method text.
- Nutrition, prices, meal slots (breakfast/lunch/dinner), copying whole weeks, marking meals cooked, multiple recipes from one photo. (iCloud sync was a non-goal through v0.4; Phase 9 builds it.)

## 3. Core flow

1. **Add recipe:** scan pages with the document camera, or pick existing photos. Up to 3 pages.
2. **Extract:** pages are resized and sent to the API. Show progress; allow cancel.
3. **Review:** page images alongside extracted title, yield and ingredient rows. The user edits, adds or deletes rows, then saves. Low-confidence rows and model warnings are highlighted. Save is blocked until the recipe has a base yield.
4. **Portions:** on the recipe screen, "Recipe serves [4]" (from the book, editable) and "I want [1]" stepper, with the factor shown (×¼). Ingredient quantities update live.
5. **Export:** "Add to Reminders" opens a sheet with every ingredient ticked except staples. The user adjusts ticks, confirms the target list, and taps "Add N items". "Share" sends the same ticked lines as plain text.
6. **Plan:** the Plan tab shows one week. "Add meal" on a day picks a recipe from the library (or scans a new one, which lands on that day); each meal has its own portions. Meals move between days by long press → Move to, by swiping, or by "Add to plan…" from a recipe. "Shop" exports the whole week (Phase 6).

## 4. Screens

- **Plan (first tab):** one week, a section per day (today marked), previous/next/Today, "Clear week". Each planned meal row: thumbnail, title, the recipe's star rating if any, "for N servings" with a stepper, book and page, a tick once exported. Long-press menu and leading swipe: Move to another day; trailing swipe: Remove; long-press-drag reorders within a day. "Add meal" per day opens the library picker (searchable, with "Scan new recipe").
- **Recipes (second tab):** list or grid of recipes with thumbnail, title, star rating if any, target portions and "Last added to Reminders" date if any. Sort by newest, title, rating or last added to Reminders; group by book. "Add recipe" button. On iPad, a split view: list on the left, recipe on the right.
- **Capture:** document camera or photo picker, page thumbnails with reorder/delete, "Extract" button.
- **Review / Edit recipe:** title, optional source note ("Book name, p.88"), yield fields, warnings banner, ingredient rows. Each row edits structured fields: quantity, max quantity, unit (picker), package size, name, preparation, optional, scalable. The raw printed text is shown read-only under each row.
- **Recipe detail:** page photos, a 1–5 star rating (tap a star; tap the current one to clear), portions stepper, scaled ingredient list grouped by section, "Add to Reminders", "Share", "Edit", "Add to plan…" (this week or next; shows what each day already has) and the upcoming days it is planned on. Opened from a planned meal, the portions section is that meal's ("Portions for Wednesday 23 Sep"): the stepper, the scaled list and Add to Reminders use the meal's portions and leave the recipe's own "I want" alone; adding stamps the meal too.
- **Export sheet:** target Reminders list picker (defaults to last used; option to create a list called "Shopping"), ingredient checklist, "Add N items" button, confirmation ("Added 9 items to Shopping").
- **Capture, gated (Phase 7):** under Extract, "12 of 20 free scans left" / "Unlimited scans" / "No free scans until 3 Oct". Once the free scans are used, Extract becomes "Subscribe to keep scanning" and opens the paywall; the pages are kept.
- **Paywall (Phase 7):** Apple's `SubscriptionStoreView` over the two Unlimited plans with a short pitch, the prices from the store, Restore purchases, and links to the terms and privacy policy. Buying dismisses it and unlocks scanning immediately.
- **Settings → Scans (Phase 7):** the same status line; "Get Unlimited…" or, when subscribed, the period end and "Manage subscription" (Apple's sheet); "Restore purchases". Debug builds add "Use up free scans" and "Reset free scans".
- **Week export (Phase 6):** "Shop" (cart) on the Plan tab, disabled when the week has no meals. The same export sheet as a recipe, headed "3 meals · 21 – 27 Sep", over the week's merged list in one "Shopping list" section; each row captioned with the meals it covers ("BEEF RENDANG (Mon), Chickpea arrabbiata (Wed)"), staples unticked, same list picker and Share.
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

**SwiftData `Recipe` model (app target):** id, title, book, page, sourceNote (legacy), pages (downscaled JPEG data, external storage), yield, targetYield (Int ≥ 1, defaults to base yield), ingredients, warnings, plannedMeals (cascade), createdAt, updatedAt, lastExportedAt, rating (1–5, nil until rated).

**SwiftData `PlannedMeal` model (v0.3):** id, dayKey (`PlanDay.isoString`, "2026-09-21"), order (position within the day), portions (Int ≥ 1, the meal's own), recipe (inverse of `plannedMeals`; deleting the recipe deletes the meal), createdAt, exportedAt.

**`RecipeCore` planning types:** `PlanDay` (a calendar day with no time zone; Codable as its ISO string; calendar arithmetic) and `PlanWeek` (seven days from the calendar's first weekday — Monday in en_GB). Fixtures in `fixtures/planning/`.

**Settings:** defaultRemindersListID, staples (default: salt, black pepper, olive oil, vegetable oil, water; matched case-insensitively against `name`).

## 6. Extraction API

`POST /extract`

- Headers: `x-app-key` (shared secret), `x-device-id` (random UUID created on first launch, stored in Keychain), and from Phase 7 `x-entitlement` (the app's current Unlimited transaction as Apple signed it — a compact JWS — when subscribed).
- Body: `{ images: [{ mediaType: "image/jpeg", data: "<base64>" }] }` — 1 to 3 images.
- Responses:
  - `200 { recipe: { title, yield, ingredients }, warnings: string[] }`
  - `401` bad app key · `402 { error: "free_quota_exhausted", limit, retryAfterSeconds }` free scans used and no entitlement · `413` too large · `422 { error: "no_recipe_found" | "unreadable" }` · `429` rate limited · `502 { error: "model_invalid_output" }`

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

**Shop for the week (v0.3, Phase 6)**
- Input: every planned meal of the week on screen whose recipe still exists, in day order then plan order, each at its own portions (factor = portions / base yield, or 1 without a usable base yield, as on the recipe screen).
- Merge rule — combine only where it is simple: rows merge when the trimmed, case-folded `name`, the unit (`each` for a quantified row without one; none for an unquantified row) and the `packageSize` all match — including twins inside one recipe (rendang lists lemongrass in the main list and in the paste: the week shows `Lemongrass stalk — 2`). Quantities are summed *unrounded* (each row's quantity × its meal's factor; unscalable rows contribute as printed; ranges end to end, a missing max counting as the min) and rounded once per §7, so 133.3 g + 133.3 g is 270 g, not 260, and 800 g + 800 g becomes 1.6 kg. Unquantified twins ("salt, to taste") collapse to one row; a quantified "salt — 1 pinch" stays separate. `optional` survives only if every contributor was optional. Anything else — tbsp vs ml, g vs kg, a 400 g tin vs a 227 g tin, "onion" vs "onions" — stays a separate row. A row fed by a single ingredient row is byte-identical to that recipe's own export line.
- Reminder title = line text. Notes = one line per contributing meal, in week order: `BEEF RENDANG · for 4 · Mon 21 Sep`.
- Share text: `Week of 21 Sep`, one line per meal (`Mon · BEEF RENDANG — for 4 servings`), a blank line, then the ticked rows; header only when nothing is ticked.
- On success: `exportedAt` on every meal that contributed to a ticked row (the green tick on the plan) and `lastExportedAt` on that meal's recipe, so the Recipes tab shows "Added to Reminders" for it exactly as a single export would. A recipe whose rows were all unticked is not stamped.

## 9. Security, privacy, cost

- The Worker checks `x-app-key`, enforces a per-device rate limit (default 30 extractions/day, counted on attempts) and a max body size.
- **Free tier and Unlimited (Phase 7).** A scan is one extraction that returns a recipe. Free: `FREE_SCANS` in any rolling `FREE_WINDOW_DAYS` per device — 20 in 30 for release, **temporarily 100** while the app is in private use (`ScanAllowance.freeScans` and `api/wrangler.jsonc` must agree). Enforced twice: the app (StoreKit 2 entitlement + a Keychain ledger of successful scans, so a reinstall doesn't reset it) decides before calling, and the Worker keeps its own count of successful scans per device and answers 402 past it unless the request carries `x-entitlement`. **For now the Worker accepts a well-formed `x-entitlement` without verifying it** — the same trust as the shared app key — so a patched app could still scan freely; before public release the Worker must verify the JWS signature chain against Apple's root and the device must prove itself with App Attest (Phase 8).
- Set a monthly spend limit in the Anthropic Console.
- The shared app key can be extracted from the app binary. Acceptable for personal and TestFlight use only; replace with real authentication before any public release.
- Page images go only to the Worker and are not stored there. They are kept, downscaled, with the extracted data on the user's devices and — from Phase 9 — mirrored to **the user's own private iCloud database**. Nothing of a user's library is ever on our infrastructure; the Worker sees an image for the length of one extraction and keeps none of it. §10 "Later — a shared week" extends this to a guest, who sees a projection of the library in a shared CloudKit zone the owner can revoke.

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

**Phase 5 — Planner (v0.3)**
- `PlanDay`/`PlanWeek` in `RecipeCore`; `PlannedMeal` model with a lightweight migration of existing stores; `PlanEditor`; Plan tab (week view, add from library or scan, portions per meal, move/reorder/remove, week navigation, clear week); "Add to plan…" on the recipe; welcome and splash copy.
- ✅ Existing recipes survive the schema change on a device. A meal added on Monday can be moved to Friday and back, reordered, given its own portions, and is still there after a relaunch. Deleting a recipe removes it from the plan. Weeks start on the locale's first weekday (Monday in the UK).

**Phase 6 — Shop for the week (v0.3)**
- `WeekShopping` in `RecipeCore` with fixtures for the merge rule; the export sheet generalised over recipe or week content; "Shop" on the Plan tab.
- ✅ On a device: a week with two recipes sharing onion, garlic and oil exports one merged row for each, notes list both meals, staples arrive unticked, the Recipes tab shows "Added to Reminders" for both recipes, and a single recipe's "Add to Reminders" is unchanged. **Accepted on the device 2026-09-21.**

**Phase 7 — Free scans and Unlimited (v0.4)**
- `ScanAllowance` in `RecipeCore`; the Worker's free window and `x-entitlement`; StoreKit 2 `SubscriptionStore`, Keychain `ScanLedger`, `ScanQuota` gate; paywall, capture footnote, Settings → Scans; `RecipeBasket.storekit` for local testing.
- ✅ In the simulator with the StoreKit configuration (run from Xcode): the count goes down per successful scan, the 21st (101st for now) shows the paywall, buying Unlimited unlocks it at once and the Worker logs `entitled: true`, expiring the test subscription brings the free count back. **Simulator leg accepted 2026-09-22.** On the phone (no products until App Store Connect): the free tier counts and gates — still open.

**Phase 9 — iCloud sync (v0.5)**
- The schema goes CloudKit-legal (`SchemaV1` frozen, `SchemaV2` current, `AppMigrationPlan` between them); the iCloud entitlement and container `iCloud.com.leonparsons.RecipeBasket`; `AppModelContainer` migrates locally, then opens mirrored, falling back to local when iCloud is unavailable; Settings → Sync says truthfully what is happening.
- ✅ In the suite: the CloudKit rules hold for every model (including a mirrored container actually loading the schema), and a real V1 store on disk migrates to V2 with every value intact. On **two devices signed into the same iCloud account**: a recipe scanned on one appears on the other with its page images; a meal added to Thursday on one shows on the other, and a portions change travels back; deleting a recipe removes it and its planned meals on both; edits made in airplane mode land when the network returns; a fresh install pulls the existing library down rather than starting empty.
- **Partly accepted 2026-09-23** on Leon's iPhone (iOS 27.0) and iPad (iPadOS 18.7.8), which is a better test than two matched devices — the same schema across two OS generations. Verified: the V1 → V2 migration ran on the phone's real store with all 5 recipes, 9 page images and 9 planned meals intact and the uniqueness constraints gone; a fresh install on the iPad pulled the whole library down from iCloud, page photos and star rating included, over about five minutes; a meal moved on the iPad appeared on the phone. **Still to check: deleting a recipe propagating, and edits made in airplane mode landing on reconnection.**

**Phase 8 — Verified entitlements (before public release)**
- The Worker verifies `x-entitlement` (JWS signature chain to Apple's root, bundle id, product id, expiry, not revoked) and App Attest proves the device; products created in App Store Connect with the same ids; real terms and privacy pages.

**Later:** on-device extraction with Apple's Foundation Models framework to remove the API cost, storing method text, and a **shared week** (below). iCloud sync moved out of "Later" and became Phase 9.

### Later — a shared week

Invite someone else to a week's plan. Both people see the same days; both can add meals, change portions, move meals between days and remove them. **The guest plans; the owner curates** — that line settles most of the rest of the design.

Decided (Leon, 2026-09-22), so this is the shape it takes when it is built:

- **Invite by link**, accepted in the app, with no account to create. Apple Accounts carry the identity, the invite is a system share sheet, and nothing new is stored on our side. Our own accounts and backend are explicitly not the plan.
- **Correction (2026-09-23): not `CKShare` over the SwiftData store.** That was the original wording here and it describes something that does not exist — SwiftData mirrors to the *private* database only, and Apple's DTS has confirmed the shared database is unsupported. `CKShare` shares a **custom record zone**, which SwiftData does not expose. The route chosen instead: SwiftData keeps local truth and the private mirror, and a purpose-built layer publishes a **projection** — the week, plus title, source, ingredients, rating and a thumbnail for each library recipe, never the full page scans — into a shared zone carrying the `CKShare`. Guest writes come back through the same zone. See `docs/DECISIONS.md`.
- **The share is the week, plus read access to the owner's library.** A guest adding a meal to Thursday picks from the recipes the owner already has — the same searchable picker the owner uses, minus "Scan new recipe". The guest sees titles, photographs and ingredients so they can choose properly; they do not get a copy that outlives the share.
- **A guest cannot scan.** No new recipes, no edits to the ones that exist. Only the owner adds to the library. This keeps the owner's collection theirs, and it means a shared week can never spend an extraction the owner did not ask for — the free tier and the API bill stay exactly as they are today.
- **Last-writer-wins per meal.** Two people rarely touch the same meal in the same second, and a merge UI for "Sara set Wednesday to 4 while you set it to 2" costs far more than it is worth. Portions, order and the set of meals are all small independent values.
- **The export stays personal.** Whoever taps Shop gets the week's list in *their* own Reminders. Reminders lists are already shareable if people want that; we should not try to own it.

Two things to do at implementation time, not before:

- ~~**Restate §2 and §9.**~~ Done in Phase 9: §2 now reads "no accounts of ours", and §9 says page images and extracted data live on the user's devices and in their own private iCloud. Neither ends up on our servers, which is the property both rewrites preserve.
- ~~**Land iCloud sync first.**~~ Done: that is Phase 9. A shared week is a synced week plus permissions; there is no sensible order the other way round.

## 11. Fixtures

**Planning (`fixtures/planning/`, Phase 5–6):** `weeks.json` pins `PlanWeek` boundaries (Monday-first and Sunday-first, a year boundary, the UK clock changes). `week-export/` has one case per file for the merge rule — meals from `fixtures/expected/` (rendang + arrabbiata, the same recipe twice, two curries at different factors) or inline, with the expected ids, titles, notes, contributors and staples, plus `01-….txt` for the share text.

### Scaling and formatting fixtures (Phase 0)

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
4. Should the week export offer "since last shop" (only meals not yet exported) once the weekly rhythm settles?
5. Unlimited prices (placeholders in `RecipeBasket.storekit`: £1.99 / month, £14.99 / year) and the terms and privacy URLs (`Legal` in `Subscription/Products.swift` points at example.com until real pages exist).
