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
