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
