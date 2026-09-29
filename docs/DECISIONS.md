# Decisions

Running log. Newest at the bottom. Format: date · decision · reason.

## Phase 0 — scaffold and RecipeCore

### 2026-09-19 · Toolchain

- **Xcode 26.3 (17C529)** at `/Applications/Dev Tools/Xcode.app` (installed from the terminal, not `/Applications/Xcode.app`), Swift 6.2.4, iOS 26.2 SDK, iOS 26.3 simulator runtime. **XcodeGen 2.46.0** (latest release). macOS 15.7.3.
- `xcode-select -p` pointed at Command Line Tools (Swift 6.1.2) when Phase 0 started. Until `sudo xcode-select -s "/Applications/Dev Tools/Xcode.app"` is run (needs the user's password), every build/test command is prefixed with `DEVELOPER_DIR="/Applications/Dev Tools/Xcode.app/Contents/Developer"` so `swift test`, `xcodebuild` and `simctl` use the same toolchain.
- Simulator used for commands: **iPhone 17 Pro** (iOS 26.3).

### 2026-09-19 · Repository layout

- Replaced the stock Xcode template (project at the repo root, iOS 26.2 deployment target, Swift 5 mode, `com.example.Recipe-Basket`) with the CLAUDE.md layout: `ios/project.yml`, `ios/RecipeBasket/`, `ios/Packages/RecipeCore/`, `docs/`, `fixtures/`. Only the asset catalog (AppIcon, AccentColor) was carried over.
- `CLAUDE.md` moved to the repo root so Claude Code loads it; `SPEC.md` moved to `docs/SPEC.md` as the spec itself asks.
- The generated `ios/RecipeBasket.xcodeproj` is **git-ignored**. CLAUDE.md forbids hand-editing it, so regenerating from `project.yml` is the only path and there is nothing to diff. Flip this if a committed project ever becomes useful (e.g. CI without XcodeGen).
- Bundle identifier: `com.leonparsons.RecipeBasket` via `options.bundleIdPrefix`. One-line change in `project.yml`. No `DEVELOPMENT_TEAM` is set; the user sets it in Xcode when a physical device is first needed (Phase 4).

### 2026-09-19 · Swift / package settings

- `Package.swift` uses `swift-tools-version: 6.0`, not 6.2. Everything Phase 0 needs (Swift Testing, `swiftLanguageModes: [.v6]`, `.iOS(.v17)`) exists at 6.0 and it keeps `swift test` working with either toolchain on this machine.
- `RecipeCore` builds in Swift 6 language mode with the default (`nonisolated`) actor isolation: it is a pure value-type library and every public type is `Sendable`.
- App target: Swift 6 language mode plus Xcode 26's `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (the settings the Xcode 26 template already applied). XcodeGen's preset default is `SWIFT_VERSION = 5.0`, so `6.0` is set explicitly.
- Info.plist is generated from build settings (`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_KEY_*`) rather than a checked-in file. Usage-description strings for the camera and Reminders are added the same way in Phases 2 and 4.
- Tests use Swift Testing. The RecipeCore tests find `fixtures/scaling/` by walking up from `#filePath`; SwiftPM resources cannot reference a directory outside the package without symlinks, and this works identically under `swift test` and the simulator test run.

### 2026-09-19 · SPEC clarifications made while building RecipeCore

Each of these is a place where SPEC v0.2 was silent, overlapping or contradictory. The tests in `ios/Packages/RecipeCore/Tests/` pin the chosen behaviour.

1. **`Ingredient.id` is app-assigned, not part of the extraction contract.** SPEC §5 puts `id: UUID` in the model that is "mirrored by the Worker's Zod schema", but the model cannot emit UUIDs. `Ingredient` decodes `id` when present and generates one when absent; it is always encoded. The Zod schema (Phase 1) and `fixtures/expected/` will carry no `id`.
2. **`Confidence`** was referenced but never defined → `enum Confidence: String, Codable { case high, low }`.
3. **Rounding bands are half-open**: `[0, 10)` → 0.5, `[10, 100)` → 5, `[100, 1000)` → 10, `[1000, ∞)` → promote. SPEC §7 wrote them with shared endpoints. Promotion to kg/l happens when the *rounded* value reaches 1000, so 999 g scaled becomes `1 kg`, never `1000 g`.
4. **fl oz shows decimals like oz** (`0.5 fl oz`). SPEC §7 lists decimals for g/ml/kg/l/oz only, but fl oz rounds to ½ exactly as oz does. lb and pint keep fractions (`1¼ lb`).
5. **Ranges share one display unit**, chosen from the upper value; both ends are rounded in it (`900–1100 g` × 1.05 → `0.95–1.16 kg`). If the ends coincide after rounding the range collapses to a single value.
6. **Staples match exactly** (trimmed, case-folded): "sea salt" is not "salt". Substring matching would make "salt" hit "salted butter". Variants are added in Settings (Phase 4).
7. **A quantity with no unit reads as `each`** in the formatter. SPEC §5 says `unit` is nil only when `quantity` is nil; Zod enforces that in Phase 1, RecipeCore stays lenient.
8. **Unscaled values recognise every common vulgar fraction** (⅛ ⅙ ⅕ ¼ ⅓ ⅜ ⅖ ½ ⅗ ⅝ ⅔ ¾ ⅘ ⅚ ⅞) within ±0.01, else show a trimmed decimal (≤ 2 dp). Rounded values only ever produce the §7 sets.
9. **Pluralisation** lives in `Unit.displayName(plural:)`: tin→tins, pinch→pinches, bunch→bunches, dash→dashes, splash→splashes, cup→cups, pint→pints; g, kg, oz, lb, ml, l, tsp, tbsp and fl oz are abbreviations and never pluralise (SPEC §7 listed only four of them).
10. **kg/l stay "as printed" at 2 dp** even when small: 1 kg ÷ 8 → `0.13 kg`, not `125 g`, because rule 6 forbids conversion. Candidate for a later relaxation (demote below 1 kg/l); not changed.
11. **"Capitalised" = first character only** (`Plain flour`, never `Plain Flour`).
12. **Decimal separator is always "."**, independent of device locale, matching every example in the spec and keeping reminder titles stable.
13. Not changed, flagged for Phase 1: the closed `Unit` enum will meet real pages ("2 rashers bacon", "1 stalk lemongrass", "a knob of butter"). Decide then between a prompt rule (unknown count words → `each`, keep the word in `name`) and adding `other` + `unitText`.
14. Not changed: per-device rate limiting with an extractable shared key is cost smoothing, not protection (SPEC §9 already accepts this); the Console spend cap is the real control.

### 2026-09-19 · Project generation and test run

- `xcodebuild test` on the iPhone 17 Pro simulator runs both `RecipeBasketTests` and, via the scheme's `package: RecipeCore/RecipeCoreTests` entry, the whole RecipeCore suite including the 23 fixtures (the `#filePath` lookup works inside the simulator).
- `GENERATE_INFOPLIST_FILE` has to be a project-level setting: the unit-test bundle needs a plist too, and XcodeGen only writes one when `info:` is given.
- The build log shows `appintentsmetadataprocessor warning: Metadata extraction skipped. No AppIntents.framework dependency found.` for every target. That is a build-tool notice Xcode 26 prints for any target not linking AppIntents (the stock template prints it too); it is not a compiler diagnostic and does not appear in Xcode's issue navigator. "No warnings" in the definition of done means compiler diagnostics (`file:line:col: warning`), of which there are none.
- The test bundle links `RecipeCore` directly (in addition to the host app) so it can `import RecipeCore`. Both are static, pure-Swift, no ObjC classes, so no duplicate-class warnings.

## Phase 1 — extraction API and evals

### 2026-09-20 · Toolchain

- Node 25.7.0 (nvm), npm 11. Pinned: `@anthropic-ai/sdk` 0.127.0, `hono` 4.13.8, `zod` 4.6.5, `wrangler` 4.135.0, `vitest` 4.1.11 + `@cloudflare/vitest-plugin` 1.1.13 (the current Cloudflare docs use the plugin, which requires Vitest ^4.1 — not Vitest 5), TypeScript 5.9.3 (7.0 is the brand-new native compiler; too fresh for the tooling around it), `tsx` for scripts, `sharp` for eval image preparation.
- Three tsconfigs: `src` (workers types), `scripts` (node types), `test` (plugin + vite/client types). Fixtures reach the workerd test runtime through Vite's `import.meta.glob` because `node:fs` is not available there.
- `wrangler.jsonc` with `nodejs_compat`; non-secret config in `vars`; secrets only in `.dev.vars` / `wrangler secret put`. The KV namespace id is a placeholder until deployment.

### 2026-09-20 · Contract

- `api/src/schema.ts` is the source of truth; `npm run schema` exports `ExtractionResponseSchema` to `schema/extraction.schema.json`. The Vitest suite fails if the file on disk is stale; the Swift `ContractTests` decode every `fixtures/expected/*.json` and compare `Unit`/`Confidence` raw values with the enums in the exported file.
- Every key is always present, `null` when absent. Structured outputs always emit every key and Swift's `decodeIfPresent` reads null as nil, so this is the strictest convention that costs nothing.
- `id` is not in the contract (Phase 0 decision 1). `packageSize.unit` mass/volume-only, positive quantities, `quantityMax > quantity` and unit-with-quantity are Zod refinements: validated client-side, retried once, never part of the grammar.
- Accepted media types: `image/jpeg`, `image/png`, `image/webp` (the spec said JPEG only; all three are supported by the API and the app can send any of them).

### 2026-09-20 · Worker

- **Structured outputs with our own JSON Schema, not the SDK's `zodOutputFormat`.** The SDK's transform drops `enum` (and everything except type/properties/required/anyOf/format/items) into the description text, which would make the closed unit list advisory. `buildModelOutputJSONSchema()` keeps enums and strips the keywords the grammar rejects (`minimum`, `minLength`, …); the reply is parsed with `JSON.parse` + `ModelOutputSchema.safeParse`. Confirmed live: structured outputs + image input works on Sonnet 5 and Opus 5, so the strict-tool-use fallback from SPEC §6 was not needed.
- The model output is a flat `{ status, recipe, warnings, reason }` object rather than a union — top-level `anyOf` is not documented for structured outputs — and `status` is how the 422 codes (`no_recipe_found`, `unreadable`) are signalled. The exported contract stays `{ recipe, warnings }`.
- Error codes beyond SPEC §6: **400 `bad_request`** (malformed body, non-UUID device id) and **503 `upstream_unavailable`** (Anthropic 429/5xx/network after the SDK's own retries); 502 `model_invalid_output` means exactly "invalid output twice". 500 `server_misconfigured` when a secret is missing.
- **Daily quota in Workers KV** (`quota:<device>:<UTC date>`, 48 h TTL). Cloudflare's Rate Limiting binding only offers 10 s / 60 s windows, so it cannot express 30/day. Eventually consistent — a burst may briefly exceed the limit — and it counts attempts before the model call so failures cost an attempt. `Retry-After` is the time to UTC midnight.
- A fresh `Anthropic` client per request (`maxRetries: 2`, 120 s timeout); no module-level state. `max_tokens` 8000 leaves room for adaptive thinking (on by default on Sonnet 5 / Opus 5; no `budget_tokens`). `ANTHROPIC_EFFORT` is optional; unset means the API default.
- One JSON log line per request (request id, device-id prefix, model, outcome, attempts, usage, latency) — never image data or model text.
- Prompt caching not used: the system prompt is ~1.5k tokens and images change per request. The structured-outputs schema adds ~4k input tokens per request (the API injects it); still cheap, revisit only if volume grows.

### 2026-09-20 · Prompt rules that go beyond SPEC §6 (all encoded in `api/src/prompt.ts` and the expected fixtures)

- Closed unit list (Phase 0 item 13): count nouns not in the list → `each`, noun kept in `name` ("4 rashers of smoked pancetta" → 4 each "smoked pancetta rashers"; "1 stalk lemongrass" → "lemongrass stalk"). The spice "2 cloves" → 2 each "cloves"; `clove` is reserved for garlic.
- Lengths ("4cm piece of ginger", "2cm stick of cinnamon") → quantity 1, unit each/stick, length kept in `preparation`.
- A bracketed weight after a counted item is `packageSize` — the size of the stated amount: "1 bunch of dill (20g)", "½ a head of broccoli (160g)" → 0.5 head, 160 g. Known wrinkle: scaling a fractional count keeps the bracketed weight unchanged ("1 head (160 g)" after ×2), because package sizes never scale; the raw text is shown in review.
- "a pinch/handful of" → quantity 1 with that unit; "a large handful" → preparation "large". "1 teaspoon each cumin and coriander seeds" → two entries. Alternatives ("or plain yoghurt") stay in `preparation` and produce a warning.

### 2026-09-20 · Eval

- `fixtures/expected/` was **transcribed by hand from the photos** (130 lines), not drafted by the model, so the eval is not grading the model against itself. Ten facing photo pages are negatives that must come back `no_recipe_found` / `unreadable`.
- Matching rule: names normalised (lower case, NFKC, punctuation stripped, naive singular), exact match first, then containment either way, one-to-one. Quantity/unit exact match is strict (numeric with 1e-6 tolerance, unit enum equality). Yield accuracy = quantity, max and unit all equal.
- **Results, 2026-09-20, prompt v1, default effort, 10 pages / 130 lines / 10 negatives:**

  | model | recall | precision | qty & unit exact | yield | negatives rejected | mean latency | tokens in / out | cost per run |
  |---|---|---|---|---|---|---|---|---|
  | claude-sonnet-5 | 100 % (130/130) | 100 % | 100 % | 10/10 | 10/10 | 15.6 s (max 37 s on a 23-line page) | 71.7k / 20.9k | $0.35 |
  | claude-opus-5 | 100 % (130/130) | 100 % | 100 % | 10/10 | 10/10 | 13.7 s | 71.7k / 15.3k | $0.74 |

  126/130 predicted names were character-identical to the transcription; the other four were rewordings ("large onion" → "onion" + preparation "large"). Both models clear the SPEC §10 targets (≥ 95 % recall, ≥ 90 % quantity-and-unit) with no headroom to distinguish them, so **`claude-sonnet-5` stays the default** (half the cost). Opus 5 was slightly faster here; at this sample size that is noise.
- Caveat: these are clean, modern, well-lit hardback pages from three books. The eval set needs harder cases before the numbers mean much more — older typography, imperial/dual units, two-column lists across a page turn, glare, handwriting, "Serves 4–6" and "Makes 12" yields, an actual sub-recipe reference. `npm run eval:draft` drafts expected files for new photos; drafts must be hand-checked before moving into `fixtures/expected/`.
- A full run costs ≈ $1.09 for both models (my plan estimate of $0.55 missed the injected schema tokens and the 20 negative calls).

### 2026-09-20 · Not done in Phase 1 (deliberately)

- Not deployed. To deploy: `npx wrangler login`, `npx wrangler kv namespace create QUOTA` (paste the id into `wrangler.jsonc`), `npx wrangler secret put ANTHROPIC_API_KEY`, `npx wrangler secret put APP_KEY`, `npm run deploy`. The app (Phase 2) needs the URL and the same APP_KEY.
- The Anthropic Console spend limit (SPEC §9) is the user's to set.

## Phase 2 — capture and review

### 2026-09-20 · Configuration

- The Worker URL and app key reach the app through `ios/Config/Secrets.xcconfig` (git-ignored; `options.preGenCommand` copies the committed `Secrets.example.xcconfig` on a fresh clone) → Xcode build settings → a real, generated `ios/RecipeBasket/Info.plist` (`RBAPIBaseURL`, `RBAppKey`). This replaces the Phase 0 `GENERATE_INFOPLIST_FILE` choice for the app target: custom keys cannot be expressed as `INFOPLIST_KEY_*`, and the plist also needs `NSCameraUsageDescription` and `NSAllowsLocalNetworking` (plain-http localhost for `wrangler dev`). The test target keeps the generated plist. `AppConfiguration` rejects placeholders so a missing key surfaces as "App not configured", not a 401.
- The app key is extractable from the binary; SPEC §9 accepts that for personal/TestFlight use.

### 2026-09-20 · Swift 6 in the app target

- With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, every non-UI type in the app target is declared `nonisolated` (`AppConfiguration`, `KeychainStore`, `DeviceIdentity`, `CapturedPage`, `ImageProcessing`, `ExtractionClient`, `ExtractionError`, `RecipeDraft`, `AddRecipeFlow.Route`) so tests and background tasks can use them. `@Model` classes and views stay main-actor.
- `Unit` clashes with Foundation's `Unit` in files that import SwiftUI; the app writes `RecipeCore.Unit`.
- `PhotosPicker`'s label closure is `@Sendable`; main-actor state read inside it is a warning, so label text is computed outside.

### 2026-09-20 · Model and persistence

- `Recipe` stores `yield: RecipeYield` and `ingredients: [Ingredient]` as SwiftData Codable attributes; the round-trip test proves every field survives, so no JSON-blob fallback was needed.
- Page images are `RecipePage` rows (`index`, `@Attribute(.externalStorage) imageData`) with cascade delete, because `.externalStorage` applies per `Data` attribute, not to `[Data]`.
- `targetYield` defaults to the base yield rounded (≥ 1); `Recipe.init(draft:)` is the only constructor, so a recipe can't be created without passing the draft's save gate.

### 2026-09-20 · Capture and upload

- Photo-picker data is resized through ImageIO's thumbnail path (`kCGImageSourceThumbnailMaxPixelSize` 1568, `…WithTransform` for EXIF orientation, JPEG 0.8) so a 12-MP HEIC never gets fully decoded; document-camera `UIImage`s take a renderer path to the same output. A phone's own JPEG can be smaller than the 0.8-quality re-encode (429 KB vs 361 KB for the rendang page); what matters is the 5 MB per-image budget.
- `AddRecipeFlow` owns the pages for the whole add-recipe sheet; the extracting and review screens only read them, so an error or a trip back never loses a page (SPEC §10 Phase 2). Cancelling an upload cancels the URLSession task; the Worker still counts the attempt (Phase 1 decision).
- `ExtractionClient` maps `URLError` connectivity codes (not connected, connection lost, cannot connect/find host, DNS, timeout, roaming/data off) to `.offline` — the "airplane mode" message — and everything else to `.network(description)`. Every `ExtractionError` carries its own title, message and `canRetry`.
- The iOS 26.3 simulator reports `VNDocumentCameraViewController.isSupported == true`, so "Scan pages" shows there too; the real camera path remains a device check.

### 2026-09-20 · Review screen

- Rows show the RecipeCore `lineText` at factor 1 with the printed line underneath and a "Check" badge for low confidence; tapping opens a form with every structured field (SPEC §4 lists them as inline; eight fields per row inline is unusable on an iPhone). Section grouping follows first appearance, main list first; a new row inherits the section of the row above it.
- Save requires a base yield (SPEC §3) **and** a non-empty title; the blocking reason is shown under the yield fields.
- iPad regular width shows the pages in a side column next to the form; iPhone uses a thumbnail strip with a zoomable viewer.

### 2026-09-20 · Verification

- Tests: 30 app tests (configuration, Keychain, image processing, client via a URLProtocol stub, draft, SwiftData round-trip) + 37 RecipeCore, `xcodebuild test` green with zero compiler warnings.
- Simulator walkthrough against `wrangler dev`: photo picker → 1176 × 1568 page → extract (Sonnet 5, 16 s) → review with warning banner → edit a quantity (line updates live) → clear the yield (Save disables, reason shown) → restore → Save → Home lists it → cold relaunch keeps it with its thumbnail → server stopped → "No connection — your pages are still here", page intact after Back.
- Not verified here, by design: the document camera and real airplane mode (device), and the iPad side-by-side layout beyond compiling.

## Phase 3 — recipes list and portions

### 2026-09-20 · Design

- **Home is one `NavigationSplitView`** (sidebar list, detail column) for both devices: on iPhone it collapses to a stack, so a selection pushes the detail. `RecipeDetailView` is the same view in both cases.
- **`Portions`** (`Detail/Portions.swift`) is the only place the base yield and wanted portions meet: it produces the RecipeCore factor, the "×¼" text (`NumberFormatting.fraction` of the factor — "×⅖" for 5→2, decimals only when no glyph fits) and the scaled rows. `FixtureParityTests` runs all 23 `fixtures/scaling` cases through it and compares the exact `lineText`, which is the SPEC §10 Phase 3 acceptance ("the UI shows the same values as the RecipeCore fixtures").
- `targetYield` is clamped to 1…999 (spec silent). The stepper and the editable "Recipe serves" field write straight to the SwiftData model, so target portions persist without an explicit save; "Recipe serves" refuses empty/zero (the field reverts on blur) so a saved recipe always has a factor.
- **Review and Edit share `RecipeFormView`**; `IngredientEditView` works on any `RecipeDraft` binding. `Recipe.apply(draft)` writes title/source/yield/rows/warnings back and bumps `updatedAt`; pages, `targetYield` and `createdAt` are untouched. `RecipeDraft(recipe:)` reads page sizes from the JPEG headers (`ImageProcessing.pixelSize(of:)`) rather than decoding.
- Section grouping moved to `[Ingredient].sectioned` / `[ScaledIngredient].sectioned` (`Models/IngredientSections.swift`) so review, edit and detail agree on the order (first appearance, main list first).
- "Add to Reminders" and "Share" are not shown until Phase 4 — no dead buttons.

### 2026-09-20 · Things found while running it

- **Deleting from inside the detail crashed** (`SwiftData/BackingData.swift: This backing data was detached from a context without resolving attribute faults … RecipePage.imageData`): after `save()`, the list row was still rendering the deleted recipe's thumbnail. The detail now only dismisses and asks `HomeView` to delete; `HomeView` clears the selection, deletes, and saves on the next main-actor turn; rows and the detail skip models whose `isDeleted` is set. Deletion is the owner's job, never the view that is showing the object.
- **iOS 26 nests `.secondaryAction` toolbar items** inside its own "More" menu, so a `Menu` placed there was two taps deep. Edit and the ⋯ menu now share a `ToolbarItemGroup(placement: .primaryAction)`.
- The Phase 2 store upgraded in place: the Beef rendang saved before Phase 3 (including its edited "750 g" row) opened in the new detail without migration, since no attribute changed.
- On iPad the add-recipe sheet is compact width, so the review form uses the thumbnail strip there; the side-by-side pages column only appears when the form is in a regular-width container (the edit sheet has the same behaviour).

### 2026-09-20 · Verification

- `xcodebuild test`: 38 app tests (incl. the 23-case parity suite, portions, `targetYield` persistence, `apply(draft)`) + 37 RecipeCore, zero compiler warnings; `swift test` unchanged.
- iPhone 17 Pro: open the saved recipe → step to 1 serving (×¼: "Beef shin — 190 g", "Cinnamon stick — ¼ stick") → cold relaunch keeps "I want 1 serving" → Edit, change the title, Save → detail and list update → ⋯ → Delete recipe… → confirmation → list.
- iPad Pro 13-inch (M5): sidebar + detail side by side; stepping to 6 (×1½) updates the detail and the sidebar row together; 800 g → "1.2 kg", "1½ handfuls", "4½ cloves".

## Phase 4 — export

### 2026-09-20 · Design

- **`ShoppingExport` in RecipeCore** owns the last formatting rules: reminder title = `ScaledIngredient.lineText`, notes = "Recipe title · for N" (N = target portions, no unit — SPEC §8 verbatim), share text = "Title — for 1 serving" + blank line + one ticked line per row, no trailing newline. Only "servings" is singularised; other yield units print as-is. Pinned by `fixtures/export/beef-rendang-for-1.{json,txt}`; writing that fixture by hand caught two errors in my own assumptions (the transcription says "large onion"; "water" is a default staple).
- **EventKit, add-only** (CLAUDE.md rule 9): `EventKitRemindersStore` requests full access (`requestFullAccessToReminders`), lists calendars, and adds one `EKReminder` per ticked line with `save(_, commit: false)` + a single `commit()`. It never fetches reminders. `saveReminder` is imported into Swift as `save(_:commit:)`.
- **"Shopping" is created in the source of the default Reminders list** (iCloud on a normal phone, Local in the simulator), or reused if one already exists there — no "Shopping 2".
- **Write-only access** (iOS 17+ lets the user pick it) can't enumerate lists; the sheet then exports to the default list and says so. Denied/restricted shows guidance with "Open Settings" and keeps Share live (§8, §10).
- Settings are two values in `UserDefaults` (`ExportSettings`): the remembered default list (last successful export wins; "Ask each time" resets it) and the staples list, normalised (trimmed, lower-cased, unique). Matching stays exact (Phase 0 decision 6). The Settings screen also shows the API host so a device build reveals which Worker it talks to.
- One export sheet serves both "Add to Reminders" and "Share" so they use the same ticks (§8 "the same ticked lines"). Duplicates are never checked for: exporting twice doubles the items, by design.

### 2026-09-20 · Simulator walkthrough (iPhone 17 Pro, real EventKit)

- Prompt shows our usage string → **Don't Allow** → "Reminders access is off" with Open Settings; Share still opens the share sheet and Copy puts the §8 text on the pasteboard (20 lines: header, blank, 18 non-staple rows at 1 serving; salt and water excluded).
- `simctl privacy reset` → **Allow** → sheet at "For 1 serving", default list "Reminders", staples unticked and labelled, "Add 19 items" → list picker groups by account ("Local") → **Create "Shopping"** → selected → Add → "Added 19 items to Shopping." → second export defaults to Shopping and adds again → the Reminders app shows **Shopping 38**, titles exactly `lineText`, notes "Beef Rendang · for 1". The recipe row shows "Added to Reminders 20 Sep 2026".
- Settings: adding "sugar" as a staple untickes "Sugar — ¼ tsp" on the next export ("Add 18 items").
- **Grocery-type lists cannot be tested in the simulator**: without an iCloud account, Reminders' List Info offers no list type, so the "Groceries" conversion (and its automatic sectioning by item name) is a device check. EventKit exposes no API to create or detect that type either; the user converts the list in Reminders.
- Reminders displays items in its own order (manual sort of insertion), not page order — acceptable; the notes carry the recipe.

### 2026-09-20 · Not yet done (device pass)

- Deployment (`wrangler login`, KV namespace, secrets, `npm run deploy`), `RB_API_BASE_URL` → the workers.dev URL, signing team in `Secrets.xcconfig` (`RB_TEAM_ID`), install on the iPhone, and the SPEC §10 device acceptance including the Grocery-list observation.

### 2026-09-21 · Deployment and device build

- Worker deployed to **https://recipe-basket-api.recipe-basket-api.workers.dev** (Cloudflare account leonpaulparsons@gmail.com). KV namespace `QUOTA` id `a99437ed2a2940b8839ac8a803141076` is in `wrangler.jsonc`; secrets `ANTHROPIC_API_KEY` and `APP_KEY` set with `wrangler secret put`. Two lessons: a fresh workers.dev subdomain fails TLS for ~1 minute after the first deploy (wait, don't debug), and a pasted secret can be silently truncated at the prompt — the 401 on the first smoke test was a 31-character `APP_KEY`; piping the value from `.dev.vars` into `wrangler secret put` avoids it.
- Smoke test through the deployed Worker: 200 in 6.9 s, 7/7 lines.
- Device build: `ios/Config/Secrets.xcconfig` now points `RB_API_BASE_URL` at the workers.dev URL and carries `RB_TEAM_ID = F6VXT39M7H` (Personal Team; found via the Apple Development certificate's OU, since Xcode's Accounts pane doesn't show the id). `xcodebuild -destination 'platform=iOS,id=<hardware UDID>' -allowProvisioningUpdates` signs and provisions without opening Xcode; the phone needed Developer Mode (Settings → Privacy & Security, restart, confirm) and a one-time profile trust (Settings → General → VPN & Device Management). Installed and launched with `xcrun devicectl`.
- App icon added (basket glyph, light/dark/tinted), rendered by an AppKit script.

### 2026-09-21 · Product change: book and page per recipe

- Feedback from the first device build: recording the book and page means only the ingredient list needs photographing — the method stays in the book. Capture now asks for **Book** (required, pre-filled with the last one, recent-books menu) and **Page** (optional, number pad). `Recipe.book`/`page` replace the free-text `sourceNote` (kept read-only for older rows). List, detail and share text show "Book, p. N".
- Contract change: `recipe.title` is nullable (a photo of just the list has no title; the prompt forbids inventing one) and the app pre-fills "Book, p. N" as the editable title. Mirrored in `RecipeCore.ExtractedRecipe.title: String?`, the exported JSON Schema, and both contract tests.
- Cost per extraction, measured: ≈ 2–4¢ on Sonnet 5 (≈ 5.5k fixed input tokens — injected schema + system prompt — plus ≈ 1.5k per photo; output 0.7–2.3k). The 30/day cap bounds a device at ≈ $1.20/day.

### 2026-09-21 · Product changes from using the app

- **Serves / Makes** replaces the bare "Unit" field on the yield (feedback: "what will be here other than serving?"). Serves stores the unit `servings`; Makes exposes the unit ("muffins"). The last Makes unit is kept while toggling so a slip doesn't lose it. Detail reads "Recipe serves" / "Recipe makes".
- **Welcome page** on first launch (name, tagline, three lines on what the app does) until the user taps Get started; re-showable from Settings → About. Stored as `welcome.hasSeen` in UserDefaults.
- **Splash** on every cold launch — branded, with a spinner — 1.5 s was the recommendation over the requested 5 s; then lengthened to **1.9 s** on request. One constant, `SplashView.duration`.
- **Sort and group** on the recipe list (⋯ menu): Newest first / Title / Last added to Reminders, and group by book (books alphabetical, page order inside, "No book" last). Pure logic in `RecipeListOrdering` with tests; choices persist in UserDefaults.
- **Star rating** (1–5, `Recipe.rating: Int?`, nil until rated — a lightweight migration). It is the cook's verdict on the recipe, so it lives on the recipe rather than the planned meal, is set on the recipe screen (tap a star; tap the current one to clear) and never by the review/edit form, and shows on every recipe tile: the Recipes list, the plan rows and the "Add meal" library. The Recipes list gains a Rating sort (highest first, unrated last).
- **Page photos open full screen** from the list thumbnail (the row's other area still opens the recipe), the recipe's new thumbnail strip, and the review form: swipe between pages, pinch or double-tap to zoom. Zooming is a `UIScrollView` wrapped in `UIViewRepresentable` — SwiftUI on iOS 17 has no zoomable scroll view, and the point is reading the printed list, so a real one was worth the ~80 lines.

## Phase 5 — planner

### 2026-09-21 · Design

- **Why:** the weekly routine still had a manual half — choosing days, shuffling, reusing recipes, compiling the week's shop. Decisions with the user: any number of meals per day (no slots); portions per planned meal, starting from the recipe's "I want"; Plan is the first tab; the week export (Phase 6) merges exact matches only and the per-recipe export stays untouched.
- **`PlanDay` / `PlanWeek` in RecipeCore.** A day is stored as its ISO string (`dayKey`), so `#Predicate` compares strings, sorting is chronological, and a time-zone change can never shift a meal. Week boundaries come from the calendar's `firstWeekday` (Monday in en_GB); `fixtures/planning/weeks.json` pins Monday- and Sunday-first weeks, the year boundary and both UK clock changes.
- **`PlannedMeal`** with a cascade from `Recipe.plannedMeals`: deleting a recipe removes it from the plan (the dialog says so). **Lightweight migration verified**: the simulator's store, written by the Phase 4 schema, opened with the new `ZPLANNEDMEAL` table and both recipes intact; no `VersionedSchema` needed. Apple's SwiftData migration pages are JS-rendered and couldn't be fetched, so this was checked empirically rather than from the docs.
- **`PlanEditor`** is the only writer of planned meals and keeps each day's `order` dense; `PlanOrdering` holds the pure grouping/reindexing. `AppSchema.models` lists every model for the app and the tests, so a model missing from the schema fails in tests before a device.
- **Screens:** `RootView` tabs; `PlannerView` (title "This week" / "Next week" / "Last week" / "Week of 21 Sep", ‹ › and Today, Clear week, Settings) over `WeekView`, which fetches every planned meal and filters by the week on screen: a `@Query` predicate is fixed at init, and recreating the view per week (`.id(week.start)`) made the navigation title vanish and reappear on every ‹ › tap (Leon's first bug report). Rows navigate to the recipe; the portions stepper sits inline; Remove is a trailing swipe; **Move to** is a leading swipe and the long-press menu; long-press-drag reorders within a day (`.onMove` works without edit mode on iOS 17+).
- **Drag between days was tried and dropped.** `.draggable`/`.onDrag` + `.dropDestination` on List rows never started a drag session in the simulator (three variants, with and without the context menu), and it would have replaced the native in-day reorder. The long-press menu is the way across days; `PlanEditor.move(_:to:at:)` keeps the drop position for a later attempt on a device.
- **"Add to plan…"** on the recipe opens a two-week day picker showing what each day already has; the recipe detail lists its upcoming planned days. `AddRecipeView` hands back the saved `Recipe` so a scan from a day's "Add meal" lands on that day.
- Welcome and splash tagline: "From cookbook page to weekly plan and shopping list."; the welcome gains a "Plan the week" row.

### 2026-09-21 · Device feedback: portions changed on the recipe didn't reach the plan

- The Plan row navigated to the plain recipe screen, whose "I want" stepper edits `Recipe.targetYield` — a different number from the meal's own `PlannedMeal.portions`, so a change there never showed on the plan. Rather than couple the two (portions are per meal by decision), the detail screen now takes the `PlannedMeal` when reached from the plan: the section is titled "Portions for Wednesday 23 Sep" with a footer saying the recipe's own portions stay as they are, the stepper and the scaled list are the meal's, and Add to Reminders exports at the meal's portions and stamps `PlannedMeal.exportedAt` as well as `Recipe.lastExportedAt` (the row's green tick becomes true before Phase 6). From the Recipes tab nothing changes.

## Phase 6 — week export

### 2026-09-21 · Design

- **`WeekShopping` in RecipeCore** merges only on an exact key — trimmed, case-folded name + effective unit + package size — because anything fuzzier (plurals, "red onion" vs "onion", tbsp into ml) is guesswork the cook would have to check anyway, and a duplicate row in Reminders costs nothing (SPEC §1). So g and kg of the same thing are two rows (no unit conversion, rule 6), as are "onion" and "onions". The key is the row's `id`, which keeps ticks stable and the list free of duplicates by construction.
- **Sum unrounded, round once.** Each contribution is quantity × its meal's factor, unrounded; the total goes through the same `Rounding.roundRange` that `Ingredient.scaled(by:)` now uses (extracted from it so there is one rounding path). Unscalable rows ("for frying") contribute as printed — not scaling with portions still means buying that much. A row fed by one ingredient row goes through `scaled(by:)` itself, so it is byte-identical to the recipe's own export line (tested).
- **Twins inside one recipe merge too** (rendang's lemongrass in the main list and in the paste → one row for 2). Same rule, and the shopping list wants the total; the recipe's own export still lists both rows.
- **Day text is supplied by the app** (`PlannedMealExport.dayText` / `weekdayText`), formatted with the user's locale as the planner already does. RecipeCore stays locale-free and the fixtures are literal strings.
- **One export sheet, two builders.** Instead of a separate `WeekExportSheet`, `ExportContent` carries rows (stable string ids), heading, subject, section title, share text and the stamps; `ExportModel`/`ExportSheet` don't know whether it is a recipe or a week, so the access flow, list picker, "Create Shopping", All/None and Share are shared as they are. `RemindersStoring.add` takes `ReminderItem` (title + notes) — it never needed ingredient ids.
- **Stamps:** adding sets `exportedAt` on every meal that contributed to a ticked row and `lastExportedAt` on its recipe (the same field the Recipes tab already reads), so the Recipes tab updates exactly as after a single export; a recipe whose rows were all unticked is left alone. The single-recipe export from the plan (previous fix) stamps the meal the same way.
- The meals `@Query` moved from `WeekView` to `PlannerView` so the Shop button and the sheet see the week on screen; `WeekView` is now a plain view of its rows.
- Checked in the simulator: four rendang meals at ×¼, ×¾, ×¼ and ×1 gave `Beef shin — 1.8 kg` with four note lines in the Reminders app; green ticks on the plan rows; "Added to Reminders 21 Sep 2026" on both recipes; Shop disabled on an empty week.

### 2026-09-21 · Accepted

Phases 5 and 6 accepted by the user on the device ("Phase 5 is good", "Looks good"). v0.3 is complete: SPEC §10 Phase 5–6 criteria met; the "Later" list (iCloud sync, on-device extraction, method text, public release) is the next conversation.

## Phase 7 — free scans and Unlimited

### 2026-09-22 · Design

- **Why now:** before the App Store polish, the API cost needs a lid: 20 scans per rolling 30 days free, Unlimited by subscription (monthly + yearly, no trial, price TBC in App Store Connect). No paid membership yet, so everything runs against a local StoreKit configuration.
- **Where it's enforced — "device now, Worker ready".** Leon asked whether device-only would be safe for public use; the honest answer was no: the Worker spends the money and trusts a shared key that ships in the binary. So the app gates (StoreKit 2 entitlement + a Keychain ledger of successful scans, which survives reinstall like the device id) *and* the Worker counts successful scans per device in KV and answers **402 `free_quota_exhausted`** past the limit. The app sends its signed transaction as `x-entitlement`; the Worker accepts any well-formed JWS for now — the same trust level as the app key, no worse than today — so that verification (Phase 8) needs no app update. Rotating device ids is closed by App Attest, also Phase 8.
- **402 rather than 429** so the app can tell "pay or wait a month" from "try again after midnight" and show the paywall instead of a retry message.
- **The Worker counts successes for the free tier but attempts for the daily cap.** A failed extraction shouldn't cost a free scan (the app counts the same way, so the two ledgers agree); the daily cap is abuse control and stays as it was.
- **A scan is one extraction that returns a recipe**, whatever the page count — matches how the app and the Worker already meter.
- **`SubscriptionStoreView` over a custom paywall:** Apple's view renders the plans, prices, intro offers, restore and policy links the way App Review expects, for ~30 lines. Product ids by `productIDs:` rather than a group id, so nothing depends on the numeric group App Store Connect will assign.
- **Temporarily 100 free scans** (Leon, 2026-09-22) while the app is in private use: `ScanAllowance.freeScans` and `FREE_SCANS` in wrangler.jsonc, with `releaseFreeScans = 20` kept beside it and the tests pinned to 20 so nothing moves when it goes back.
- **StoreKit tests under `xcodebuild`:** on the iOS 26 simulator, command-line test runs don't push the scheme's StoreKit configuration, so `SKTestSession` fails with `SKInternalErrorDomain 3` (Apple forums confirm; running the app from Xcode once fixes it for that simulator). `SubscriptionStoreTests` record a known issue in that case rather than failing; the gate itself is tested with a fake entitlement source. Apple's `StoreKitTest` headers also emit a deprecation warning under Xcode 26 — silenced for the test target only (`-Xcc -Wno-deprecated-declarations`).
- Placeholders that must be real before submission: prices, `Legal.terms` / `Legal.privacy` (example.com).

### Open: device acceptance (SPEC §10 Phase 4)

Awaiting the user's device pass: document camera, export at 1 portion, titles/notes, staples unticked, duplicate export, denied permission + Share, and the Grocery-list section behaviour.

### 2026-09-22 · StoreKit tests under `xcodebuild` — the earlier note was half right

- Running the app from Xcode fixes less than assumed. Only Xcode's own launch path (Cmd-R, Cmd-U) syncs the scheme's StoreKit configuration to the simulator, over an XPC call `xcodebuild` has no equivalent for. A Cmd-R installs it for the **app**, so `Product.products(for:)` starts answering, while `SKTestSession` stays inert: every session write returns `SKInternalErrorDomain 3` and `buyProduct` throws `StoreKitError.notEntitled` ("Failed to purchase … in off-device buy mode"). The suite's escape hatch was keyed on the products being missing — the wrong signal — so the Cmd-R turned a recorded known issue into a hard failure.
- **Both are probed now**: missing products *or* a `.notEntitled` purchase record a known issue naming the remedy ("run the tests from Xcode (Cmd-U)"); every other purchase error propagates as a real failure, so a genuine `SubscriptionStore` bug still fails the run. `xcodebuild test`: 84 tests pass with one known issue.
- **The scheme cannot carry it.** `storeKitConfiguration` under a scheme's `test:` action is accepted by XcodeGen 2.46 and silently dropped — it only ever writes `StoreKitConfigurationFileReference` into `LaunchAction`. `xcodebuild` exposes no flag for it either. So the StoreKit lifecycle is genuinely exercised only from Xcode; the command line covers the gate through the fake entitlement source, as before.

### 2026-09-22 · Accepted (Phase 7, simulator leg)

Leon ran the full SPEC §10 Phase 7 walkthrough from Xcode against `RecipeBasket.storekit`: the free count goes down per successful scan, the gate shows the paywall at the limit, buying Unlimited unlocks scanning at once with the Worker logging `entitled: true`, and expiring the test subscription brings the free count back.

Still open: the **phone leg** of Phase 7 (the free tier counts and gates on the device — no products there until App Store Connect), the **Phase 4 device pass** noted above, and all of Phase 8 before any public release.

## Design pass — Page & Plate

### 2026-09-22 · The name, and how far it reaches

- **Page & Plate** replaces the working name Recipe Basket, chosen by Leon. Everything a user can see changes: `CFBundleDisplayName`, the splash and welcome, the paywall, both Info.plist usage strings, the Reminders permission copy, and the subscription's display name in `RecipeBasket.storekit`.
- **Internals keep the old name on purpose**: the bundle id `com.leonparsons.RecipeBasket`, the Xcode target and scheme, the repo folder, and the StoreKit **product ids**. The bundle id is welded to the provisioning profile on the phone, the Keychain scan ledger and the Worker's per-device KV keys; product ids are never shown. Renaming them would reset the free-scan ledger and buy nothing. Revisit only if Leon wants a clean id before submission — it costs a re-provision.
- Still to do before submission: reserve the name in App Store Connect, and rename the subscription group and products there to match.

### 2026-09-22 · A design system, and why the accent was the whole game

- **`ios/RecipeBasket/Brand.swift`** now holds the name, tagline, palette, display face and the mark. The brand colours and the name/tagline were previously copy-pasted into `SplashView` and `WelcomeView`; there is one copy of each now. `Brand.name` and `Brand.tagline` are `nonisolated` so off-main-actor code (`RemindersStore`) can build messages from them — the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, so without it a plain `static let` is main-actor bound.
- **The accent was never wired up at all.** `AccentColor.colorset` was empty *and* `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` was unset, so filling the colour set alone changed nothing — Xcode's own templates set that build setting, XcodeGen does not. Both are fixed; the whole app is now tomato instead of system blue, which was the single highest-value change in the pass.
- **Colours were picked for contrast, not just hue.** The old tomato `#ED5C33` is 3.2:1 on a light ground, below the 4.5:1 floor, so it could tint a shape but never set text. `#B23A1B` is 5.6:1 on paper and 6.0:1 under white — it works as a label *and* as a fill. Dark-mode pairs were checked the same way (`#F2775A` at 6.4:1 on `#1A1713`).
- **Paper and ink over the old gradient wash.** Gradient-plus-rounded-sans is the default look of the moment; a warm paper ground with a serif display face reads as a cookbook and is what Apple's editorial team weights most ("design-aware app with a distinctive UI"). Applied to the branded surfaces (splash, welcome) in this pass; the List screens still use system materials, which is deliberate — they get dark mode and Dynamic Type for free.
- **Display face: SF Serif for now.** `Brand.display(_:)` uses Fraunces when the file is bundled and falls back to `.system(design: .serif)`, which is on-device. The canvas was designed in Fraunces; bundling it is one font file plus `UIAppFonts`, and nothing breaks either way. Verified on the simulator that the fallback looks right.
- **The system launch screen had no colour**, so a cold launch flashed white before the splash. `UILaunchScreen` now names a `LaunchBackground` colour set matching `Brand.paper`; the two read as one screen.

### 2026-09-22 · The mark, and the icon script

- The mark is a plate seen from above holding an open book — the shopping basket belonged to the old name. `BrandMark` draws it in a SwiftUI `Canvas` from a 100 × 100 space, so it takes the current foreground colour and stays sharp at any size rather than shipping as an asset.
- **`ios/Tools/RenderAppIcon.swift` is committed this time.** The script that drew the first icon was never checked in (noted 2026-09-21), so re-rendering meant rewriting it. It draws the same geometry as `BrandMark` into three 1024 PNGs with no alpha, and is run with `swift ios/Tools/RenderAppIcon.swift`.
- **The mark is inset to 78% of the tile** (`markFraction`). Drawn edge to edge it crowded iOS's rounded mask and read far heavier than in the app; the first correction to 66% then left it looking small on the home screen (Leon, on the phone). 78% is the settled value — big enough to read at Spotlight size, still clear of the mask corners. Both errors were caught by looking at the rendered PNG and the springboard, not by reasoning about it.

### 2026-09-22 · Copy

- Welcome rows cut from 25–40 words each to a title plus one short sentence. The paywall leads with "Scan as many pages as you cook" instead of opening on our API costs; the free-scan count and the cancel note follow.
- The review screen was titled "Review" and the capture screen "Add recipe"; both are now "New recipe". Leon's note on the store frames applies to the app itself: the app is meant to make life easier, so the screen where the model has just done the work shouldn't read like marking homework.
- Verified on the simulator in light and dark: splash, welcome, Settings → Scans, and the tint across the Plan tab.

### 2026-09-22 · A shared week — the shape it will take

Not built, and not next; recorded so it is not re-argued from scratch. Leon's calls, in SPEC §10 "Later — a shared week":

- **Invite by link, no accounts of ours.** CloudKit sharing (`CKShare` over the SwiftData store) — Apple IDs carry the identity and nothing lands on our side. Our own backend is explicitly off the table, which keeps the privacy story and the running cost where they are.
- **The guest plans; the owner curates.** The share is the week plus *read* access to the owner's library, so a guest filling in Thursday picks from recipes the owner already has. Same picker, minus "Scan new recipe".
- **A guest cannot scan or edit recipes.** This was the question left open yesterday — who pays when a guest scans — and the answer is that they can't, so it never arises. A shared week can never spend an extraction the owner did not ask for, and the free tier and the Worker's metering stay exactly as they are. SPEC §12 question 6 is struck as answered.
- **Last-writer-wins per meal**, because portions, order and the set of meals are small independent values and a merge UI would cost more than the conflicts it resolves.
- **The export stays personal** — whoever taps Shop gets the list in their own Reminders.
- **Two edits deferred to implementation time**, now flagged by a forward reference at both sites so neither reads as a hard rule: §2's "single user, single device, no accounts" becomes "no accounts of ours"; §9 is a *different* point — it says extracted data and page images live on device only, and sync plus a share moves them into the user's own iCloud. Nothing lands on our servers either way, which is the property both rewrites must keep. And iCloud sync has to land first — a shared week is a synced week plus permissions.

### 2026-09-23 · Screenshots, and two things they exposed

- **The pages are ours.** `fixtures/photos/` is real cookbook pages, personal-use-only, so they cannot appear in marketing. Three pages were written and designed for this instead (`marketing/pages/`), with ingredients chosen to exercise the scaler and to overlap each other so the week-export frame has real merges. Rendered with `marketing/tools/html2png.swift` and put in the simulator's photo library with `simctl addmedia`.
- **`html2png.swift` goes via WKWebView's PDF output, not `takeSnapshot`** — the snapshot path crashes inside WebKit when run from a `swift` script. PDF is vector, so rasterising at a scale stays sharp, and it writes with no alpha channel, which App Store screenshots require.
- **Captures are native.** `simctl io <device> screenshot` writes 1320 × 2868 on an iPhone 17 Pro Max and 2064 × 2752 on an iPad Pro 13-inch, which is what guarantees Apple's dimensions rather than resizing afterwards. Frames are authored at a third (440 × 956) and rendered at 3×.
- **The iPad set reused the iPhone's data** by copying the app's SwiftData container between simulator containers (`simctl get_app_container … data`, then copy `Library/Application Support`). Saved three extractions and about 9p; worth remembering.
- **Found: every export-sheet row rendered in the accent colour.** The row's `Text` sets `.primary` and `.secondary`, but the enclosing `Button` tints its whole label and wins. `.buttonStyle(.plain)` restores the intent. This predates the rebrand — it was blue before and read as ordinary interactive rows; tomato made it obvious. Fixed in `ExportSheet.swift`.
- **The scaler agrees with the design.** Every value drawn in the frame mockups turned up identical in the real app: `½ tsp` from the 1½ ÷ 4 tie case, `40 g` from 37.5 on the 5 g band, `¼ tin (400 g)`, `¾–1 clove`. The one difference was naming — the model extracted "Large onion", not "Onion", so onions did **not** merge across recipes in the week export. That is the exact-match rule behaving correctly, and a good live example of why the merge is deliberately narrow.
- **Not done:** frame 1 shows a flat digital render of a page rather than a photograph of a printed one, and it reads as one. Printing at A5 and reshooting would improve it; nothing else in the set depends on it.

### 2026-09-23 · The app's ground is paper, not systemGroupedBackground

- Leon noticed the screenshots did not match the mockups: "more peachy in the mockup". He was right, and it was a call I made in the design pass without flagging clearly — `Brand.paper` went on the splash and welcome only, and every `List`/`Form` kept iOS's default. Sampled: the mockup ground is **#FAF7F0** (red channel highest, warm); `systemGroupedBackground` is **#F2F2F7** (*blue* channel highest, cool). Literally opposite temperatures, which is why it read as a subtle wrongness rather than an obvious one.
- **`.paperBackground()`** now pairs `.scrollContentBackground(.hidden)` with `Brand.groupedPaper`, applied at all eleven `List`/`Form` sites. Leaving one out is what makes the difference visible, so they all get it.
- **`.listRowBackground` on a `List` is silently ignored** — it does not reach the rows. The first attempt set it there and dark mode came back with the system's #1C1C1E card on our #1A1713 ground, near-invisible. Rows keep their own system fill instead, which adapts on its own.
- So the ground splits in two: **`Brand.paper`** for full-bleed brand surfaces (splash, welcome) stays #1A1713 in dark, and **`Brand.groupedPaper`** behind lists goes to **#0E0C0A**, dark enough that the system's card fill separates the way it does on stock iOS. The same split Apple makes between `systemBackground` and `systemGroupedBackground`.
- All nine frames reshot. Light and dark both checked on device-sized simulators.

### 2026-09-23 · Planned meal rows: portions above the stepper

- Leon's call from looking at the screenshots: move "for N servings" out of the left column and put it above the +/− stepper. It reads as one control instead of a stray line, and it takes a line out of the *tallest* column, so the whole row shrinks. Measured: **180 → 159 pt** for a rated row, 163 → 142 pt otherwise, about 13% off every card.
- **It broke at accessibility text sizes**, which is how the change earned its keep. Side by side, neither the portions text nor the stepper can shrink, so at `accessibility-large` they crushed the title to "Chi ck…" and the thumbnail to a sliver. The old layout was tight there too; the wider right column made it unusable.
- `PlannedMealRow` now switches on `dynamicTypeSize.isAccessibilitySize`: two rows at accessibility sizes (thumbnail and details, then portions and stepper), side by side otherwise. The pieces are computed properties so both layouts share one definition. Checked at `large` and `accessibility-large`.

### 2026-09-23 · The name is reserved

- **Page & Plate** is reserved in App Store Connect, against the existing bundle id `com.leonparsons.RecipeBasket`. The App Store name and the bundle id are independent fields; Apple never shows the id to a user, so the internals keep the old name as decided above.
- **The bundle id is now fixed.** It cannot be changed once an app record exists, only deleted and recreated before the first upload. That was the last cheap moment to rename, and we deliberately did not — the id is welded to the provisioning profile on both phones, the Keychain scan ledger and the Worker's per-device KV keys.
- **The hold lapses after 90 days without a build: 6 January 2027.** Uploading anything to TestFlight resets it.

### 2026-09-23 · Phase 9: iCloud sync, and the thing the spec got wrong about sharing

- **SwiftData cannot do `CKShare`.** The spec described the shared week as "CloudKit sharing (`CKShare` over the SwiftData store)". That is not a thing. SwiftData mirrors to CloudKit's **private** database only — `ModelConfiguration.CloudKitDatabase` offers `.automatic`, `.private` and `.none`, with no shared option — and Apple's DTS has stated the public and shared databases are unsupported. `CKShare` shares a **custom record zone**, which SwiftData does not expose. Verified 2026-09-23 against Apple's forums and documentation; this is the single most useful line in this file for a future session, because the wrong premise reads perfectly plausibly.
- **Route chosen (Leon):** keep SwiftData, hand-build the share. Phase 9 is private sync and changes nothing structural. Phase 10 publishes a *projection* of the library and the week into a shared zone — title, source, ingredients, rating, a thumbnail, never the full page scans — which also happens to honour §9 better than sharing the store would have. The alternative, moving the store to Core Data + `NSPersistentCloudKitContainer`, is Apple's supported sharing path but replaces SwiftData across the whole app; parked as the fallback if the projection proves unworkable.
- **Three schema rules, and the test that actually enforces them.** CloudKit refuses a store with uniqueness constraints, non-optional attributes lacking defaults, or non-optional relationships. `Recipe.id` and `PlannedMeal.id` lost `@Attribute(.unique)` (nothing relied on it — both are a fresh `UUID()` at init), every non-optional attribute gained a default, and `pages`/`plannedMeals` became optional. The optionality cost almost nothing because no call site outside `Recipe.swift` touched `recipe.pages` — they all went through `orderedPages`; `plannedMeals` got a matching `meals` accessor.
- `CloudKitSchemaTests` checks the rules by reflection *and* by loading a real mirrored container on disk. The second is the one that matters: Core Data runs its own validation at load and refuses the store, so a future `@Model` property without a default fails in the suite instead of silently stopping sync on a phone. That is exactly how the error surfaced during this work.
- **`Schema(versionedSchema:)`, not `Schema(models)`.** The first migration attempt failed with `loadIssueModelContainer` because the store was never stamped with a version identifier, so `AppMigrationPlan` had nothing to recognise. Same for the app's own container.
- **A `ModelConfiguration` defaults to `cloudKitDatabase: .automatic`.** The V1 fixture store in `SchemaMigrationTests` failed to load until it was given `.none` — V1 is precisely the shape CloudKit rejects, which is why the migration exists. Easy to lose an hour to.
- **Two opens at launch** (`AppModelContainer`): migrate against a local store, then open mirrored. It keeps a schema change and CloudKit's setup out of the same open, and it means a build without the entitlement, or a device with no iCloud account, still gets a correctly migrated store. A failure to open *any* store is a `fatalError` — launching with an empty library is indistinguishable from losing it.
- **Settings → Sync has no toggle.** Sync follows the device's iCloud account, so the only honest thing to offer is a status line and a sentence saying the data goes to the user's own iCloud and never to ours.
- **Still open:** the CloudKit schema is created in the *development* environment on first run and must be pushed to production before submission. Added to `docs/APPSTORE.md`.

### 2026-09-23 · Phase 9 on two devices, and an iPad sidebar that was never there

- **Phase 9 accepted 2026-09-23**, both legs. Leon's iPhone (iOS 27.0) and his iPad (iPadOS 18.7.8) — a better test than two matched devices, since the same schema has to hold across two OS generations. The V1 → V2 migration ran on the phone's real store: 5 recipes, 9 page images, 9 planned meals all intact, uniqueness constraints gone, CloudKit metadata tables created. A fresh install on the iPad pulled the entire library down from iCloud, page photos and star rating included, over about five minutes. A meal moved on the iPad appeared on the phone. Deleting a recipe removed it and its planned meals on both, and edits made in airplane mode landed on reconnection — both confirmed by Leon on the devices.
- **Enrolling did not register the iPad.** `-allowProvisioningUpdates` would not add it from the command line and neither would Xcode; the device had to be registered by hand in the portal. The iPhone never needed it because it was already registered from the free-provisioning era. Expect this for every new device.
- **The provisioning profile now runs a year** (to 2027-09-23) and the iCloud container registered itself during the first device build. The 7-day reinstall treadmill is over.
- **Read a device store with its `-wal` and `-shm`, or you will read a lie.** Copying `default.store` alone showed 1 recipe when the store held 6, because the recent transactions were still in the write-ahead log. This produced a false "sync is duplicating records" alarm and then a false "sync has stalled" one.
- **The iPad Recipes tab looked empty and was not.** `HomeView`'s `NavigationSplitView` opened with the sidebar collapsed, and the sidebar holds both the list *and* the Add/Sort/Group/Settings toolbar — so the screen had no content and no controls, which reads exactly like a sync failure. It was Leon noticing the missing `+` and `•••` that identified it, not any measurement. Now `columnVisibility: .all` with `.navigationSplitViewStyle(.balanced)`.
- This was latent from **Phase 3**: the iPad split view was written and never run on an iPad, because there wasn't one until today. A reminder that the Phase 4 device pass is still open and still worth doing.

### 2026-09-23 · Phase 10 step 1: the projection, and the assumption it rests on

- **`CKSyncEngine` and SwiftData's mirroring coexist in one container.** This was the risk the whole design depends on, so it was built and run first, on the iPad, before anything was stacked on it. Evidence rather than a status line: the engine wrote its `shared-plan-engine-state` file (it only does that once it has sent changes), five thumbnails were staged, and the SwiftData store came through with its rows and CloudKit metadata intact. Different zones — SwiftData owns `com.apple.coredata.cloudkit.zone`, we own `SharedPlan`.
- **The projection is the §9 boundary**, and two tests hold it there rather than a comment: a 400 KB page cannot survive into any record field, and no key matching "export" is ever written. The second one matters because the export staying personal (SPEC §10) is otherwise the kind of promise that quietly stops being true.
- **`SharedExportTests` is the test that proves the projection is sufficient.** A projected week produces byte-identical `WeekShopping` lines to the owner's own week from the same data — so the guest's Shop needs no separate implementation, and `PlannedMealExport` defines what the projection must carry.
- **Thumbnails reuse `ImageProcessing`** with `maxLongEdge` as a new parameter (default unchanged), rather than a second downscaler. 240 px: recognisable in a list, useless for reading someone else's cookbook.
- **Deliberately temporary:** a DEBUG "Publish the plan" button in Settings. It exists only to prove the above; step 2 replaces it with the real share entry.

### 2026-09-23 · Phase 10 step 2: invite and accept

- **Apple's sharing UI, not ours.** `UICloudSharingController` wrapped for SwiftUI — there is no SwiftUI equivalent (`ShareLink` shares a URL, not a `CKShare`). The invite goes out through Messages, Mail or a copied link with nothing of ours involved, which is the §2 promise kept rather than restated.
- **`CKSharingSupported: true`** in the Info plist. Without it a share link opens the App Store instead of the app, and the invite looks broken to the person you sent it to.
- **Acceptance needs both paths.** `windowScene(_:userDidAcceptCloudKitShareWith:)` for a tap while the app runs, **and** `connectionOptions.cloudKitShareMetadata` for a cold launch from the link. Missing the second is the usual reason share links appear to do nothing. SwiftUI still has no lifecycle hook for either, so the app now carries a scene delegate for this one job, reached through the single shared `SharedPlanMembership` — the only shared instance in the app, and only because UIKit leaves no other seam.
- **Re-inviting reuses the existing share.** `shareForInviting()` fetches the zone's share before creating one, so "Manage sharing…" twice cannot produce two plans.
- **`publicPermission = .none`**: invited people only, never anyone who comes by the link.
- **Not verifiable here.** Accepting an invite needs a *second Apple Account*; Leon's iPhone and iPad share his, so sending himself an invite exercises nothing. The acceptance path stays unproven until Sara's phone is present — recorded so it is not mistaken for tested.

### 2026-09-23 · Phase 10 step 3: the guest's week

- **A second, local-only SwiftData store** (`shared-plan.store`, `cloudKitDatabase: .none`) holds the guest's copy. Not the guest's own store: the owner's recipes must not join the guest's library, must not sync to the guest's iCloud, and must vanish when the share ends. Keeping it in SwiftData still buys offline access and `@Query`.
- **`SharedMeal` references its recipe by id, not by relationship.** A guest can receive a meal before the recipe it names, and a dangling relationship is worse than a lookup that comes good a second later.
- **`PlannedMealRow` now takes `MealRowData`, plain values.** Both weeks render through the same row, so the accessibility-size two-row layout fixed earlier today serves the guest too, rather than being quietly reimplemented and quietly regressed.
- **The guest's editing keeps the owner's invariants.** `SharedWeekClient.add/move/remove` reindex each day to 0…n-1 exactly as `PlanEditor` does, and clamp portions the same way — a guest leaving holes in the ordering would break it for both of them. Five tests hold that.
- **`isExported` is always false on a shared week.** The row can show the owner's "added to Reminders" tick, and on the shared week it never does: the export is personal both ways.
- **The switcher lives in `toolbarTitleMenu`** and only appears for a guest, so nothing changes for someone who has never been invited. The title reads "Leon · This week" when looking at someone else's, so whose meals you are editing is never ambiguous. Shop and Clear week stay disabled on a shared week for now — step 4's fold-back has to land before the guest's Shop is meaningful.
- **No "Scan a recipe" in `AddSharedMealSheet`, and that is the feature** (SPEC §10). The guest's own library and scanning are untouched; they simply cannot add to the owner's, so a shared week can never spend an extraction the owner did not ask for.

### 2026-09-23 · Phase 10 step 4: folding a guest's edits into the owner's real plan

- **The fold-back is the dangerous half.** The guest's week is a projection, but the owner's is the live `PlannedMeal` store the app runs on, so `SharedWeekFoldBack` leaves it exactly as `PlanEditor` would: each day dense at 0…n-1, portions clamped, and **`exportedAt` untouched**. Eight tests, including one that exists solely to assert a guest's edit cannot stamp the owner's meal as added.
- **A guest's meal keeps the guest's id.** Otherwise the guest's next edit to the same meal would create a second one on the owner's plan. Tested directly.
- **A meal naming a recipe the owner has since deleted is skipped, not half-applied.** The owner curates; the owner wins.
- **The echo guard.** Applying a guest's change saves the store, and the owner republishes on every save — without `isApplyingRemote` that is a loop. Republishing everything on each save is wasteful at a large library, and still cheaper than the bookkeeping to send less at the size this app holds.
- **The guest's Shop is theirs.** `ExportContent.sharedWeek` builds the same rows through the same `WeekShopping` merge, with `onAdded` doing nothing — there is nothing of the owner's to stamp, and the list lands in the guest's own Reminders. The shared week carries its own Shop button; the owner's is hidden while looking at someone else's plan, so there is never a question of which list you are about to make.
- **Still unproven end to end.** Everything above is tested against a real SwiftData store, but no guest has ever accepted an invite: that needs a second Apple Account. Sara's phone is the missing piece, and until then Phase 10 is built, not accepted.

### 2026-09-23 · Signing out of iCloud empties the local library — accepted, and said plainly

- **Found while setting up the accessibility pass**, by transplanting the iPad's store into a simulator with no iCloud account. The app emptied it on launch, and the system said exactly why: `NSCloudKitMirroringDelegateWillResetSyncNotificationName` with reason `AccountLogout`, then `Removing rows after account change: Recipe / RecipePage / PlannedMeal`.
- **Phase 9 introduced this.** Before today the store was local-only and iCloud was irrelevant to it. It is standard `NSPersistentCloudKitContainer` behaviour rather than a defect, but it is a real behaviour change, and the Phase 9 plan did not consider it.
- **Leon's call: accept it as normal iOS.** Notes and Reminders behave the same way, and the records are not lost — they stay in the user's iCloud and return when they sign back in. The loss is local and recoverable.
- **Warning before the purge was considered and rejected as unreliable, not just expensive.** The account can change while the app is not running, so on next launch the purge has already happened during store load. A "warning" would arrive after the fact about half the time.
- **What was done instead — the cheapest thing that was also the most correct: fix a sentence that had become false.** Settings said "\(Brand.name) works normally without it — everything stays on this device", written this morning and untrue from the moment sync landed. It now says signing out removes the local copy, that the recipes stay in iCloud, and that they come back on signing in again.
- **The lesson worth keeping:** the copy written for a feature can be invalidated by the same feature. This was caught by accident while chasing something else.

### 2026-09-23 · The accessibility pass

- **The export checklist was the real find.** Every row was a `Button` whose label held the tick icon, so VoiceOver read "circle, Butter beans, Smoky butter beans (Wed)" with no way to tell ticked from unticked — on the one screen whose entire purpose is ticking things. Each row is now a single element with an `accessibilityValue` of "Ticked"/"Not ticked", the `.isSelected` trait, and a hint saying what a double tap does.
- **Decorative things are hidden** rather than announced: the welcome symbols, the plus-circles that repeat the text beside them, and the page thumbnails in meal rows (a photo of a cookbook page has nothing useful to say, and the title is right next to it).
- **Meal rows read as one phrase** — "Chickpea arrabbiata, rated 4 of 5, LEON Happy Curries, p. 110" — instead of three separate stops. The stepper stays its own element so it is still operable.
- **Large type checked on a real iPad at the largest accessibility size** across the recipe screen, export sheet, Settings, Review and the paywall. Nothing broke. Worth noting this is the second time the iPad has earned its keep today.
- **Not done: a deliberate VoiceOver session.** The nomination's accessibility paragraph is a claim made to Apple, so it stays do-not-send until someone has navigated the export sheet with VoiceOver on and heard the states. The fixes above were made without hearing them.

### 2026-09-23 · Phase 4 accepted, and the grocery question answered

- **Accepted on the iPad**, every leg: denied permission shows guidance with Share still working, export at 1 portion, titles and notes to the SPEC §8 format, staples arriving unticked, a second export adding duplicates without error, and the document camera — the one leg no simulator can test.
- **The Groceries-type list sections our titles correctly.** This is the open question from the Phase 4 notes above (line ~184): the conversion needs an iCloud account, so it had never been observed, and the whole "ingredient name leads the title" decision rested on it. Reminders sorts our items into its own categories as intended. **The name-first title format is now confirmed rather than assumed** — it is load-bearing, so do not reorder it.
- Phase 4 had been open since the project had no paid account and no second device. It closed the same day the iPad arrived, alongside the Phase 3 sidebar bug the iPad also exposed — twice in one day that running on real hardware found what no test did.

### 2026-09-23 · Tell people to set the list to Groceries

- Leon's observation after the Phase 4 pass: the sectioning only happens if the user converts the Reminders list themselves, and nothing in the app ever said so. EventKit cannot create or detect a Groceries-type list (see the Phase 4 notes above), so this can only be guidance — but without it the "ingredient name leads the title" format, which the whole export is built around, pays off for nobody.
- **Two places, one string** (`ReminderListPicker.groceriesTip`): the footer under "Create 'Shopping' list", where the user is at the moment the list comes into existence, and Settings → Reminders, where someone looks afterwards. It names the exact path — List Info → List Type → Groceries — rather than gesturing at it.
- A tip on every export was considered and rejected: it would be noise on a screen people use weekly, to say something that only matters once.

### 2026-09-23 · A one-time Groceries tip after the first export

- Leon's call after the footers landed: a footer is there for someone already looking, and nobody looks. The moment that matters is the first time items reach Reminders and the user goes to see them.
- **It rides the existing "Added to Reminders" alert** rather than adding a second interruption. First export only: "Added 12 items to Shopping." plus one line — "Tip: in Reminders, List Info → List Type → Groceries sorts these into aisles." Same tap, same alert, once ever.
- **Kept to one line, and a test holds it there.** The first draft was three sentences; an alert is an interruption, not documentation, and the reference version already lives in Settings. `GroceriesTipTests` fails if the tip grows past 90 characters.
- **`GroceriesTip` is its own type, not a method on the view**, so the once-only rule is testable. `claim()` both answers and marks, which is what makes "exactly once" a single atomic thing rather than two statements a future edit could separate. Five tests.
- The flag is claimed at the moment of adding and held in `@State`, so flipping it cannot blank the tip out of the alert already on screen.
- No "Show me how" button: there is no public URL that opens a Reminders list's settings, and a button that cannot do what it says is worse than none.

### 2026-09-23 · The scan limits reshaped: 7 for life, 25 a week unnamed

- **Decision (Leon).** The free tier becomes **7 scans total** — for the life of the device, not a rolling
  window — after which the only way on is a subscription. (Set at 5 first and settled at 7 the same day, which
  is why the commit that introduced it says 5.) The subscription stops being literally unlimited and
  carries **25 scans in any rolling 7 days**, and that number is **never shown to the user**.
- **Why.** Twenty free scans every thirty days was a free product, not a trial: enough to plan a fortnight,
  reset monthly, forever. Seven once is a taste — a week of cooking, which is exactly the thing being sold. At the other end, "unlimited" had no lid on the API bill at all;
  25 a week is more than anyone cooking from books gets through, so it binds only on abuse.
- **Why the ceiling stays quiet.** A number invites counting against it — people ration long before they reach
  it, and the promise turns into a budget. The copy says "enough for everything you cook in a week"; someone who
  does reach the ceiling is told when there is room again, never how many they had. The Worker's
  `weekly_quota_exhausted` body carries `retryAfterSeconds` and nothing else, and a test asserts exactly that.
- **How it is counted.** One ledger, two shapes (`ScanTally` in RecipeCore): `total`, the lifetime count the
  trial spends, and `recent`, the dates still inside the week. Pruning drops old dates and never the total, so
  the Keychain entry stays small while the trial stays spent. Free scans fill the week too, so subscribing
  mid-week starts from the true count. The Worker mirrors both: `free:<device>` is now a bare count with no TTL,
  `week:<device>` is the rolling window it used to be.
- **Migration.** Ledgers and KV values written before today are an array of dates. Their length becomes the
  lifetime total — an undercount, since those arrays were already pruned to thirty days, which errs towards the
  user. Both sides have a test for it.
- **What this costs us.** Leon's own two devices have far more than 7 scans recorded, so the trial reads as
  spent on both. That is correct behaviour, not a bug; Settings → "Reset scans (debug)" clears it, and the
  Worker's `free:<device>` key needs clearing separately if it 402s.
- **Left open.** The plan is still *named* "Page & Plate Unlimited" while carrying a ceiling. Every other
  user-facing claim has gone ("removes the limit", "Unlimited cookbook scans", the status line "Unlimited
  scans"), but the name is itself a claim and App Review reads subscription names. Recorded as blocker 2 in
  `docs/APPSTORE.md`; the product ids stay as they are either way, since they are never shown.

## Phase 8a — Verified entitlements

### 2026-09-25 · The Worker checks Apple's signature instead of the shape of the string

- **What was wrong.** The scan gate's test for a subscription was `JWS.test(header)` — a regular expression
  for three base64url segments separated by dots. The string `a.b.c` passed it. Anyone who read the header
  name out of the binary had the unlimited tier, billed to Leon's Anthropic account. SPEC §6 said so plainly
  and had said so since Phase 7; this closes it.
- **`app-store-server-api`, not Apple's own library.** `@apple/app-store-server-library` was the obvious
  choice and the wrong one: it pulls `node-fetch`, `jsonwebtoken` and `jsrsasign`, and it requires
  `appAppleId` in Production, which we do not have. `app-store-server-api` depends only on `jose`, and its
  verification is about forty readable lines — chain dates, each certificate issued and signed by the next,
  the root pinned by SHA-256 fingerprint, then the signature checked with the leaf's key.
- **The deciding feature is the fingerprint override.** Xcode's local StoreKit configuration signs with its
  own authority, not Apple's. Without being able to point the verifier at that root, nothing bought in the
  simulator would verify and the only way to test would be the real App Store. It goes in `.dev.vars` as
  `XCODE_ROOT_FINGERPRINT`, unset in production.
- **Two things about that certificate that only the live chain revealed**, both of which cost a round trip
  to find and are worth not rediscovering. It is **generated on the machine** — `CN=StoreKit Testing in
  Xcode`, roughly a year's validity — and has to be exported with Editor ▸ Save Public Certificate. The
  static `StoreKitTestCertificate.cer` inside `IDEStoreKitEditor.ideplugin` looks like the right file and
  signs nothing. And the chain is **a single self-signed certificate**, its own leaf and root, not the
  three links Apple sends.
- **A local purchase carries `environment: "Xcode"`**, which is neither Production nor Sandbox, so the
  verifier had to learn it — gated on `allowXcodeEnvironment`, which `app.ts` sets only when the fingerprint
  override is present. Apple never issues an Xcode-environment transaction, and production sets neither
  binding, so this cannot widen anything where it matters.
- **What we gave up.** Apple's library does OCSP revocation checking of the signing certificates; this one
  does not. The case that actually matters — a refunded or revoked *subscription* — is `revocationDate` in
  the verified payload, which we check. A revoked Apple signing certificate is a risk taken knowingly.
- **A failed verification is not an error.** It means "not a subscription", and the free trial answers as it
  always did. A patched client gets 402 `free_quota_exhausted` like anyone out of scans, rather than a 401
  telling it precisely what to forge next. The request log gains `entitlementRejected` with the reason, so a
  genuine subscriber failing verification is visible rather than silently demoted.
- **Sandbox is allowed, for now.** Every purchase in development and TestFlight is a Sandbox transaction, so
  `ALLOW_SANDBOX_ENTITLEMENTS` has to be true to test at all. Left true in production it is a free
  subscription for anyone with a sandbox account, so it is a release blocker in `docs/APPSTORE.md`.
- **Tests sign their own certificates.** `scripts/make-test-pki.sh` generates two unrelated chains plus an
  out-of-date leaf, committed under `test/fixtures/pki`, so the suite needs neither Apple nor a network. It
  proves each check bites: wrong root, a leaf the intermediate never issued, a payload edited after signing,
  another app's bundle id, a product we do not sell, an expiry in the past, a revocation date, and Sandbox
  with the switch both ways. One test runs the **real** verifier rather than an injected one, so the exact
  regression that started this — `a.b.c` buying the unlimited tier — is pinned.
- **App Attest is split out as 8b.** Not for size: `DCAppAttestService.isSupported` is false in the
  Simulator and on Apple silicon Macs, so it can only be exercised on a physical device against the 7-day
  free-provisioning treadmill. 8a needed nothing but this machine, and holding it back would have bought
  nothing. Until 8b lands, a patched app can still rotate its device id for fresh trials.

## Phase 8b — App Attest

### 2026-09-25 · The Secure Enclave signs, and the trial stops being free to farm

- **What was wrong.** 8a stopped a forged subscription; nothing stopped a forged *device*. `x-device-id` is
  a UUID the app invents, so a patched build rotated it and collected a fresh 7-scan trial each time, up to
  `DAILY_LIMIT` a day per invented id, on Leon's Anthropic account.
- **The rule that carries the phase.** An assertion proves nothing on its own if the quota still counts
  against a client-chosen id: a perfectly valid signature attached to a fresh UUID would buy a fresh trial.
  So when a request is attested, **the identity the trial and the week hang off is the attested key**.
  `x-device-id` stays for the log. There is a test whose whole job is this, and it is the one to read first.
- **`@peculiar/x509`, not `node:crypto`.** Apple's nonce lives in an extension identified by OID, and node's
  `X509Certificate` — which 8a proved works in workerd — cannot read an arbitrary one. `@peculiar/x509` can,
  is WebCrypto throughout, and needs `reflect-metadata` imported before it. CBOR is
  `@levischuck/tiny-cbor`, which SimpleWebAuthn uses at the edge. Both verified in workerd and under
  `wrangler deploy --dry-run` before anything was built on them; the bundle went from 250 KB to 337 KB
  gzipped.
- **Two things the spike taught.** openssl will emit an extension whose declared length disagrees with its
  contents, and `@peculiar/x509` parses it without complaint — so the nonce is read by its declared length
  rather than sliced off the end, which would have accepted it. And Apple's devices sign DER while WebCrypto
  wants raw r‖s, so the signature is converted.
- **Tests mint their own attestations.** The nonce inside a leaf certificate is a hash of the attestation it
  sits in, so a committed fixture cannot exist; `test/appattest-fixtures.ts` generates an authority and a
  leaf per attestation. Apple's nine checks and the assertion's four each fail on their own, with no device
  and no network.
- **A challenge is spent whether or not what follows succeeds.** It is worth one attempt, not one success.
- **The Simulator changes how development works.** `DCAppAttestService.isSupported` is false there and on
  Apple silicon Macs, so `REQUIRE_ATTESTATION` is not scaffolding to be removed — screenshots, the StoreKit
  loop and most iteration happen in a simulator that can never attest. The app sends no headers there and
  the Worker decides.
- **Turning this on resets the trial.** An attested build counts against a key id rather than the old device
  UUID, so the existing `free:<uuid>` counts are orphaned and every install starts fresh once. Acceptable,
  and it happens exactly once.
- **Honest about what it is worth.** Apple does not limit how many keys a device may create, so someone with
  a real iPhone and a patched build can still farm trials. What this stops is everything cheaper: scripts,
  emulators, a leaked `APP_KEY`, and rotating a UUID in a loop. The receipt is stored, unused, so the
  risk-metric API can close the rest without re-attesting anybody.

## Phase 11a — One plan on display

### 2026-09-25 · The switcher was the wrong model

- **What prompted it.** Phase 10 shipped a segmented switcher on the Plan tab: the guest kept their own plan
  and toggled to the owner's. Leon used it and called the model wrong — a person wants one week, and the
  households are the reason to subscribe, not a side feature. Everything below follows from "one plan on
  display, ever".
- **`Households` replaces `SharedPlanMembership`.** A list rather than a single value, plus which plan is
  showing. It reads the Phase 10 defaults keys once and converts them into a one-element list, because
  Leon's iPhone, the iPad and Sara's phone all carry them and nobody should have to re-accept an invite
  they already took. The old keys are removed as they are read, so the path runs exactly once.
- **Hidden, never deleted.** Joining a household hides your own plan; your library keeps mirroring to your
  own private zone throughout, and leaving brings the week back untouched. Hosting and joining are
  independent — host a household, join someone else's, and yours keeps running for the people in it.
- **The guest store is a cache, and that is a licence.** It is local-only, and every row can be fetched
  again from CloudKit, so adding a household column shipped as a **renamed file with the old one deleted**
  rather than a migration plan. This is the exact opposite of the app's own store, where `SchemaV1` is
  frozen and a migration is mandatory; the comment in `SharedStore` says which rule applies and why, because
  the next person to touch it should not have to work it out.
- **Leaving one household must not empty the store.** `SharedStore.empty` took everything, which was right
  when there could only be one shared plan and silently destructive the moment there can be two. It now
  takes a household, and the whole-store version is kept for signing out of iCloud, where nothing shared may
  survive. Two households' weeks are also numbered separately — ordering is per household, or one week's
  meals would renumber another's.
- **Supporting several households was mostly deletion.** `CKSyncEngine` over `sharedCloudDatabase` already
  fetches every shared zone; the Phase 10 code was *narrowing* it to one. What was needed was removing that
  filter and recording which zone each record arrived from.
- **The owner names the household.** It goes on the `CKShare`'s title, so every member reads the same name.
  Phase 10 derived one from the owner's iCloud identity, which is how "Shared's plan" reached the screen —
  a name the owner typed cannot fail that way.
- **Hosting requires a subscription**, so the Settings row opens the paywall rather than sitting there
  disabled with no explanation. Membership stays free: that is the upsell.
- **The grey navigation bar fixed itself**, as predicted from reading the code. The `VStack` that held the
  switcher was stopping the List running under the bar, so the paper background stopped at the top. Removing
  the control removed the bug — which is why it was left alone rather than patched around.

### 2026-09-26 · The household's week belongs to the household, not to the owner (Phase 11b-i)

Phase 10 kept the shared week in the **owner's** `PlannedMeal` store and folded members' edits back into it.
That works while the catalogue is a copy of the owner's library. It stops working the moment the catalogue
becomes the union of everyone's, which is what 11b is for: a member can plan a meal from *another member's*
recipe, `SharedWeekFoldBack` looks that recipe up in the owner's library, misses, and returns nil — so the
meal reaches every member except the owner. A household where one person's week differs from everyone
else's is not a household.

The alternative was to give the owner read-only shadow copies of other members' recipes, which needs a
migration of the app's own frozen schema and contradicts "a recipe belongs to whoever scanned it". So the
week moved instead: it lives in the household zone, and everybody — the owner included — reads and writes it
through one local store (`SharedStore`) and one editor (`HouseholdWeekEditor`). `SharedWeekFoldBack` and its
tests are deleted; nothing folds into SwiftData any more. The asymmetry *was* the complexity.

**Hosting replaces "My plan"** (Leon's call). The alternative was a third row in Settings — your own plan,
the household you host, the households you joined — which is more uniform but adds a row most people would
never tap. So `.mine` resolves to the hosted household, and the household's week is **seeded once** from the
personal week when it is created, so the screen looks the same either side of sharing. The personal
`PlannedMeal` week is kept and hidden, per rule 9d. The cost, accepted knowingly: the owner has no way back
to their personal week while the household exists. Stopping sharing removes only the participants — the
zone, week and name survive, so it is lossless — and "delete the household and give me my week back" is 11c.

**Three defects in 11a, found by reading it rather than by running it.** None had been seen, because 11a
never reached a device:

- **Rows keyed on the zone name.** `SharedWeekZone.zoneName` is the constant `"SharedPlan"` in *every*
  owner's database; only the owner tells two households apart. `Household.id` knew that, the store did not.
  Two joined households merged into one week and one catalogue, and a write resolved to whichever household
  was joined first — so an edit could be sent into the wrong person's zone. Rows now key on `Household.id`.
- **The store was renamed without discarding the engines' change tokens.** A `CKSyncEngine` fetches only
  what changed *since* its token, so emptying the cache while keeping the token means it never refills: a
  permanently blank household, with no error anywhere. `SharedStore.generation` now names the store file and
  both engine state files, so they cannot come apart. This would have hit the iPad on its next launch.
- **Removing a meal reindexed the survivors locally and sent only the deletion**, so other members kept
  stale orders and two meals claimed one slot.

Also from 11b-i: `SharedMeal` carries the recipe **title**, so a meal whose recipe is not in the catalogue
renders as itself rather than vanishing (which is what it did); and a **local** `exportedAt` that is never
projected, restoring the "added to Reminders" tick per member while keeping the export personal. The test
asserts the *absence* of any export field on the record rather than trusting it.

### 2026-09-26 · A recipe belongs to whoever scanned it, and says so in a field of our own (Phase 11b-ii)

The plan said `CKRecord.creatorUserRecordID` would carry ownership "without a field of our own". It is
server-set and unforgeable, which is genuinely better — but it does not work here, for two reasons. The
local household store holds rows, not records, so there is nothing to ask; and CloudKit reports it
inconsistently for records the *current* user created, which would make the owner's own rows read as
`__defaultOwner__` while every member's read as a real id. "Is this mine?" would silently invert for the one
person who can remove people. So the author writes an explicit `authorID` — their `CKContainer.userRecordID()`
— and `creatorUserRecordID` is the fallback when that field is missing. **The device check that matters:**
that `userRecordID()` is the same identity `CKShare.Participant.userIdentity` reports, since the owner's
removal counts key on that equality.

**Members scan.** `AddSharedMealSheet` refused to, on the reasoning that a shared week must never spend an
extraction the owner did not ask for. That was the real argument and it stopped being true when the
allowance moved to the person: rule 9b already counts against an attested key, not a plan, so there is no
longer anyone else's allowance to spend. The scan lands in the scanner's own library and is projected from
there. The sheet takes the library container **explicitly**, because inside the household view the
environment's context is the household store, which has no `Recipe` in its schema at all.

**Departure is "stop projecting", never "delete"** — the recipes are untouched in their author's library.
Leaving withdraws them *before* the membership goes, since the membership is what resolves the zone. Being
*removed* cannot work that way: access is lost in the same instant, so the person cannot take their own
recipes out. Only the zone's owner can, so the owner prunes recipes whose author is no longer on the share.
An unattributable recipe is always kept — deleting someone's recipe on a guess is worse than leaving one too
many in a catalogue.

**Two properties the fan-out needs to be safe, both non-obvious.** The projection skips a recipe whose
already-projected row compares equal, and that skip is the *only* thing preventing an endless loop:
`ModelContext.didSave` is one notification for the whole app, so writing to the household store wakes the
watcher that writes to the household store. Filtering on the notification's object would have worked too,
but rests on which object SwiftData happens to attach; idempotence does not rest on anything. And a pass is
**all or nothing** — the local row is later read as "this household has been told", and the deletion journal
is emptied by draining it, so a half-sent pass would both mark recipes projected that were not and lose a
deletion outright. `SharedPlanContext.start()` reprojects once the engines are up, which is what closes the
gap for anything scanned before they were.

## Phase 11b-iii — the household actually syncs

### 2026-09-28 · Two causes behind seven reported bugs

Testing 11b on two phones produced seven reports: portions and moves never travelling in either direction, a
member's removal not reaching the owner, and a crash on removing a meal or on remove-then-add. Reading the code
against them found two causes, and every symptom belongs to one of them.

- **Every save after the first was refused by CloudKit and only logged.** Both engines built the record to send
  with `CKRecord(recordType:recordID:)` — a new record with no `recordChangeTag`. CloudKit accepts that once,
  because the record does not exist yet, and refuses every later save of the same record with
  `serverRecordChanged`, which Apple's documentation is explicit is the caller's to resolve and reschedule. Both
  engines wrote a log warning and dropped it. So a meal reached the household when it was created and never
  again. Fixed by keeping each row's `systemFields` (`CKRecord.encodeSystemFields(with:)`, the supported way to
  hold a record in a local database), building every record from the row, storing the metadata of every record
  the server accepts or sends down, and resolving `serverRecordChanged` by adopting the server's record and
  staging the save again.
- **Four `ModelContext`s over one container.** The facade, each engine and the views each had their own, and the
  views' `@Query` fetched in `mainContext`. Every edit was therefore made to an object registered in one context
  and saved through another: `setPortions` saved a context with nothing pending, `move` reindexed second copies
  of rows still on screen, and `remove` deleted an object out from under a live reference — the crash, and "it's
  still there when I go back in". Fixed by using `container.mainContext` everywhere; `attach` now takes the
  container rather than a context so a second one cannot be passed in.

**Why every test passed while the app was broken.** The editor tests constructed their own `ModelContext` and
handed the same one to the editor, which is the arrangement the app did not have. `editorsWriteTheContextTheViewsRead`
now pins the app's wiring instead, and the editor suite takes `mainContext` as the app does.

**Why only "add" worked.** An add inserts a brand-new object into the editor's own context and makes a first
CloudKit save, which needs no change tag. Every operation Leon found working was an add; that shape was the
clue that pointed at both causes.

`SharedStore.generation` → 3. The rows gained a field and the change tokens must go with them: a row gets its
metadata by being fetched from CloudKit, and a kept token means nothing is fetched.

### 2026-09-28 · The household has one name, and recipes say who added them

- A member now re-reads its `CKShare` on every start and whenever the shared database changes, and takes
  `CKShare.SystemFieldKey.title` from it. 11a read the title only when the invite was accepted, so a household
  carried over from Phase 10 was called "Shared plan" on the member's phone for ever while the owner saw the
  name they had typed — and a rename reached nobody. `Households.rename` is separate from `join` because a
  rename must not move what is on display.
- `HouseholdMembers` caches `authorID → name` from the share's participants, which every member can read, so a
  recipe somebody else scanned reads "Added by Sara" in the week, the catalogue and the recipe screen. An author
  whose name CloudKit has not given says nothing at all rather than "Someone" — CloudKit withholds names until
  an invite is accepted and sometimes after, so a placeholder would be the common case, and a guess is worse
  than a blank.

**Not fixed, because it was already right:** owner and member share one editor, so control of the week was
already symmetric once the context bug went; and a member has Leave and no way to remove the host, because the
member rows hang off `households.hosted` and `UICloudSharingController` offers a participant only "Remove Me".
That last one is a claim about Apple's UI, so it is on the device list rather than covered by a test.

### 2026-09-28 · Nobody names a household

Three attempts at naming one, all abandoned. Phase 10 derived a name from the owner's iCloud identity, which
produced "Shared's plan" when CloudKit would not say who they were. 11a asked the owner to type one. Today that
was tried on two phones: Sara named hers "The Parsons", and Leon's navigation bar then read "The Parsons · This
week", truncated — as any name long enough to be meaningful would be, because the title shares that bar with the
week.

So the title is computed and there is nothing to type:

- the plan that is yours to run is **"My plan"**, whether or not you host it, because you only ever own one;
- the first household you joined is **"Our plan"**;
- any after that are **"Plan 2"**, "Plan 3", in the order they were joined.

**Whose it is is what identifies it** — the owner's full name, in small text under the row in Settings, where the
household you host says "You share this one". That is a better answer than a name: a member could never rename
somebody else's household, so a name they found unhelpful was one they were stuck with.

Two consequences, both accepted. Leaving a household renumbers the ones after it — the owner's name under the
row is the part a person recognises, and it does not move. And `Household.title` is now vestigial: it still holds
the share's title and is still stored, because CloudKit's sharing UI displays it and because removing a stored
property would stop every household already on a device from decoding, but nothing reads it.

**What this deleted**, which is the argument for it: the "Name your household" prompt, `Households.rename`, the
legacy-title upgrade (`SharedWeekPublisher.upgradeDefaultTitle` and `SharedWeekZone.isAppGeneratedTitle`) and the
duplicate-name numbering added earlier the same day. All of it existed only because a household's name was user
data that could be wrong, absent, stale, or the same as another's. `HouseholdMembers` now keeps two forms of each
name from the same share — the given name for a row caption, "Added by Sara", and the full name for the line that
identifies a household, "Sara Parsons".

Also today: the Plan tab drops the week from its title once the week is only a date, so it reads "Our plan"
rather than truncating "Our plan · Week of 12 Oct". This week, last week and next week are still named. No date
is lost — every day header carries its own, and the week arrows are in the same bar.

### 2026-09-28 · CloudKit will not name anybody, so each person says

"Our plan" showed no owner beneath it on a device, twice, after re-inviting. The cause is not ours to fix:

```
CKApplicationPermissionUserDiscoverability
  API_DEPRECATED("No longer supported. Please see Sharing CloudKit Data with Other iCloud Users.",
                 ios(8.0, 17.0))
```

`CKUserIdentity.nameComponents` needs that permission, and iOS 17 removed it along with every
`discoverUserIdentity` API. A share participant's name is nil on every build this app can ship, and so is the
current user's own — no app can read its user's name from iCloud any more. The "Added by Sara" attribution
built earlier the same day rested on the same field and would never have shown anything either.

So the app asks. `HouseholdAuthor.name` is typed once, in Settings or when first sharing, and published into
every household this device is in as a `SharedMember` record — filed under the author's user record name,
carried in the zone beside their recipes, and updated like any other record (it keeps `systemFields`, so a
rename is an update rather than a tagless save CloudKit refuses). `SharedMemberRow` is the local row;
`HouseholdMembers` is the observable cache the views read.

Consequences worth stating. A person who has not set a name is **not named** rather than guessed at, so a
household can sit without an owner's name until they open the app. The name is not verified and never could be
— it is what someone asks to be called. It is visible only to the people they share with. And signing out of
iCloud keeps it, because it is theirs rather than the account's; asking again would be asking twice for the
same answer.

This is why the owner's name is worth the prompt: with households no longer named (above), it is the only
thing that identifies one.

### 2026-09-28 · The owner says they are the owner

Two bugs in the naming built an hour earlier, both invisible on screen.

**The name was never saved.** The Settings field committed on `.onSubmit`, which fires only when Return is
pressed. Typing a name and tapping another row, or closing Settings, discarded it — and the field still showed
the text while the screen was open, because it was bound to local state. It now commits when focus leaves and
when the section disappears, as well as on Return.

**The owner's name was looked up by comparing two ids from different sources.** The member record is filed
under `CKContainer.userRecordID().recordName`, read on the owner's device; the lookup used the zone's
`ownerName` as a *member's* device reports it. Whether those are the same string was listed in the plan as "the
one assumption a unit test cannot settle" — and then built on anyway. When they disagree the record arrives,
the name is stored, and the line stays blank with nothing in any log.

The assumption is now removed rather than tested. The owner sets `isOwner` on their own record, because they are
the one who knows without guessing: they are the one hosting. A member reads "the member record in this
household flagged as owner" and compares no ids at all. `HouseholdMembers.owners` is keyed on `Household.id`
for the same reason.

What is left of that assumption is safe by construction: a recipe's `authorID` and its author's member record
are both written from the same device's `userRecordID()`, so that match is self-consistent and never crosses a
zone.

### 2026-09-28 · A member record's name, and why nothing was published

The owner's name still did not appear after the two fixes above. The cause was in the record id:

> The recordName string must contain only ASCII characters, must not exceed 255 characters, and must not start
> with an underscore.

A CloudKit **user** record name always starts with an underscore — `_a1b2c3…` — and member records were filed
under the raw author id. Every save was therefore invalid and CloudKit refused all of them. Nothing surfaced,
because a refusal arrives as an ordinary failed save and the handler logged it at `warning` and dropped it: the
records existed locally, looked published, and had never left the device.

Member record names are now prefixed (`SharedWeekRecords.memberPrefix`), and `.invalidArguments` /
`.serverRejectedRequest` are logged as errors with the record name rather than folded into the default branch —
they mean the record is unacceptable to CloudKit, which is a bug, not a transient.

`SharedStore.generation` → 5, so the rejected saves still queued in both engines' state go with the tokens
rather than being retried for ever under an id CloudKit will never accept.

**The pattern across today's three naming failures is the same one:** each was a silent rejection with a
plausible-looking local state — a name saved only on Return, an id compared against a different id, a record
CloudKit would not take. None of them could be seen from the screen, and none produced an error a user or a log
reader would notice. Where a feature depends on a write reaching CloudKit, the failure path has to be loud.

### 2026-09-28 · SchemaV2 is frozen, and a meal carries a note

A planned meal gained `note`, which is the first change to the app's own store since Phase 9 — so the schema
grew a third version, and `SchemaV2` had to be frozen the way `SchemaV1` already was.

**It was not.** `SchemaV2` pointed at the live models, so adding a property to `PlannedMeal` would have
silently redefined a shipped version: V2 would have claimed a column no V2 store on disk has. Both phones are
carrying V2 stores, which makes V2 → V3 the migration that actually runs in the field — the one case that most
needs a real store written and reopened rather than a lightweight stage assumed to work. `SchemaV2` is now a
frozen storage-only copy, `SchemaV3` is the live shape, and `SchemaMigrationTests` runs both stages against
stores on disk.

The note itself: on the **meal**, not the recipe, because it is about the occasion. **Shared** with the
household, unlike `exportedAt` — the two are asserted together in one test so the difference cannot be lost.
**Not in the export**, because the shopping list is ingredients. And shown on a row as a speech bubble rather
than as text (Leon, 2026-09-28): free text of unknown length would break a row layout that already has to
survive accessibility sizes, so the glyph says there is something to read and the meal's screen is where it is
read.

### 2026-09-28 · The subscription is not called anything

"Unlimited" is gone from everything a user sees (Leon). It claimed the wrong thing in both directions: the plan
carries a real ceiling of 25 scans in any rolling seven days that is deliberately never shown (rule 9b), and
typed recipes — added the same day — are free and *genuinely* unlimited. App Review reads a subscription name as
a claim, and this one was getting harder to defend while doing less selling.

It has no replacement name. It is simply the subscription: Settings offers "Subscribe…", and the paywall is
headed with the app's own name. The subscription group is "Page & Plate" and the two products are "Monthly" and
"Yearly".

The paywall's body is now one sentence: *"A subscription covers everything you need to cook breakfast, lunch and
dinner each week, and you can cancel any time."* The trial is not mentioned — this screen is for somebody
deciding whether to pay, and their remaining free scans are counted on the screen they came from.

**Prices confirmed:** £1.99 monthly, **£19.99** yearly, matching `RecipeBasket.storekit`, whose test storefront
is now GBR so a local run shows the prices that will actually be charged.

*Corrected 2026-09-29.* This entry said £14.99 yearly and claimed it matched `RecipeBasket.storekit`, which has
said `19.99` throughout — so the sentence asserting agreement was the thing that was wrong, and it had been
copied on into `APPSTORE.md`, `SPEC.md` and the published terms page. The prose was never checked against the
file it cited. `appstore-counts.py` reads the listing table now but does not read the StoreKit config, so
nothing would have caught this.

**And `docs/appstore-counts.py` was checking strings that were not in the listing.** The in-app purchase fields
were hardcoded in the script and had drifted from the table in `APPSTORE.md`, so it reported "ok" for copy that
had not existed for weeks. It reads the table now. A checker that checks something other than the document is
worse than no checker — the same shape as today's silent CloudKit rejections, and worth noticing twice.

### 2026-09-28 · The pitch is the household

Removing "Unlimited" left the paywall with no statement of what a subscription buys, still selling scanning
alone — which stopped being the whole story the moment typed recipes became free and genuinely unlimited. What
a subscription buys that nothing else does is cooking together.

So the paywall leads with it ("Cook together, from your own books"), and every length-limited field in
`docs/APPSTORE.md` was rewritten: the subtitle trades "shop" for "together", the keywords trade `scale`,
`cooking`, `baking`, `kitchen` and `ocr` — none of which were earning their place — for `family`, `household`,
`partner` and `share`, and the description gains a COOK TOGETHER section plus the privacy line that belongs
beside it: members see the week, the titles and the ingredients, never the photographs of the page.

The welcome screen already had a household row from 11a; this phase's plan said to add one, which was wrong.

`appstore-counts.py` rejected the first draft twice, on the promotional text and the keywords. That is the
checker doing its job a day after it was fixed to read the document rather than a hardcoded copy of it.

### 2026-09-28 · Joining a household has to fetch it from scratch

Leon joined Sara's household and saw an empty week. Her meals only appeared once she changed something —
a portions edit, say — which is the shape of a change-token problem rather than a permissions or record one.

A `CKSyncEngine`'s stored state holds a change token **per zone**, and a household joined, left and joined
again is the same zone throughout: same `zoneName` ("SharedPlan" for everybody) and same owner. So the token
still said "you have seen everything up to here", CloudKit correctly reported nothing changed, and the backfill
never happened. `shareEnded` only discards the state when the *last* household goes, because the households
still joined need their own tokens — which is right, and is exactly what left the stale one behind.

`SharedWeekClient` now records which households its state has actually fetched. A joined household that is not
in that set discards the state before the engine is built, so every zone is read from the beginning. It also
calls `fetchChanges()` explicitly on start rather than leaving it to `automaticallySync`: somebody who has just
accepted an invite is looking at an empty week *now*.

Worth noting the pattern, because it is the third of its kind today: the failure was silent and looked like
nothing happening. A change token that is too new, a record name CloudKit refuses, an engine left running after
its zone was deleted — none of them produced an error anywhere.

### 2026-09-29 · Photograph the whole page, and other copy that had grown

Leon, from using it: **the guidance to photograph only the ingredient list was wrong, and had been since the
book and page fields landed.** A whole-page photograph works better, because the title is usually nowhere near
the ingredients and the extraction fills it in when it can see it — so the narrower photograph was costing a
field the app would otherwise have had. This reverses the capture note in the 2026-09-23 entry above (line
~200), which reasoned from "the method stays in the book" to "only the list needs photographing". The first
half is still true; the conclusion did not follow. The prompt already handled both framings
(`api/src/prompt.ts` sets `title` to null rather than inventing one when no title is visible), so nothing
changed on the model side.

The shipped line is Leon's, and gives the instruction without the reason: *"Photograph the recipe ingredients
page - If the recipe runs over a page turn, add the next page as well, up to N pages."* A first draft explained
why the whole page helps; it was too long for a footer somebody reads once, and the reason is recorded here
instead.

**Still inconsistent, and Leon's to call:** `docs/APPSTORE.md` still opens the description with "Photograph the
ingredient list on the page", and the featuring nomination says "Point it at the ingredient list on the page."
Both now contradict the app.

**The Reminders list type is named regionally.** It is "Shopping" on a UK device and "Groceries" on a US one,
and the copy said Groceries in both places it appears, naming a setting a UK user cannot find. It now says
Shopping, and the US aisle names ("Produce, Canned Goods") are gone rather than translated — they are regional
too, and listing them was never the point. The symbol names and the `export.hasSeenGroceriesTip` key are
unchanged: renaming the key would show the one-time tip again to everyone who has already seen it.

`GroceriesTipTests` asserted `message.contains("Groceries")`. Switched naively to "Shopping" that assertion
would have passed on the list *title* in the line above it and stopped testing anything — the sample list in
the test is called Shopping too. It now asserts against the tip line alone.

**Four Settings footers and one title, all shortened on Leon's read of them:** the Week footer loses the
"nothing moves" reassurance, Sync's signed-out line loses its second clause, Your household loses a sentence
and the "page photos are never shared" line, and Staples loses the exact-match rule. The privacy point still
lives in the App Store description and the privacy policy, which is where someone deciding goes; a Settings
footer is read by someone who has already decided. The recipes list is now titled **My recipes**, which the
household made meaningful — it queries the device owner's own library, never the household's catalogue.
