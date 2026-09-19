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
