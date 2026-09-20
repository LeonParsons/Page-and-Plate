# CLAUDE.md — Recipe Basket (working name)

Native iPhone and iPad app: photograph a recipe page → extract ingredients and yield → user confirms → scale to the portions wanted → add that recipe's ingredients to Apple Reminders (or share as text).

Each recipe is exported on its own. There is no combined shopping list and no merging of ingredients across recipes. Duplicate items in Reminders are acceptable by design.

**Full product spec: `docs/SPEC.md`.** Read it before starting any phase. Build phases in order; don't start the next phase until the current one's acceptance criteria pass.

## Stack

- **App:** Swift 6 language mode, SwiftUI, iOS/iPadOS 17 minimum, universal target (iPhone and iPad).
- **Project generation:** XcodeGen from `ios/project.yml`. Never hand-edit `.pbxproj`; change `project.yml` and regenerate.
- **Persistence:** SwiftData.
- **Capture:** VisionKit `VNDocumentCameraViewController` (wrapped for SwiftUI; auto-crops and flattens pages) plus `PhotosPicker` for existing photos. Resize long edge to ≤1568 px, JPEG quality ≈0.8 before upload.
- **Export:** EventKit (`requestFullAccessToReminders`) for Reminders; SwiftUI `ShareLink` for plain text.
- **Core logic:** local Swift package `RecipeCore` (models, scaling, rounding, fraction formatting, line formatting). Tests use Swift Testing.
- **API proxy:** Cloudflare Worker (TypeScript) + Hono + `@anthropic-ai/sdk` + Zod 4. Model name from env `ANTHROPIC_MODEL` (default `claude-sonnet-5`). API key is a Wrangler secret. Tests with Vitest.
- **Dependencies:** no third-party Swift packages without asking first.

## Layout

```
ios/project.yml               XcodeGen spec
ios/RecipeBasket/             App target: SwiftUI views, SwiftData models, VisionKit, EventKit, API client
ios/Packages/RecipeCore/      Pure Swift: Codable models, scaling, rounding, formatting (no SwiftUI/UIKit/EventKit/networking)
api/                          Cloudflare Worker: POST /extract, eval script, JSON Schema export
schema/extraction.schema.json Generated from the Worker's Zod schema; the contract between API and app
fixtures/scaling/             Scaling and formatting cases (JSON)
fixtures/photos/              Real cookbook page photos for evals
fixtures/expected/            Hand-checked expected extractions for those photos
docs/SPEC.md                  Product spec and phases
docs/DECISIONS.md             Running log: date, decision, reason
```

## Commands

Keep this section accurate as things are set up. Pick an installed simulator name when first running.

Xcode 26.3 lives at `/Applications/Dev Tools/Xcode.app`. If `xcode-select -p` still points at Command Line Tools, either run `sudo xcode-select -s "/Applications/Dev Tools/Xcode.app"` once or prefix each command below with `DEVELOPER_DIR="/Applications/Dev Tools/Xcode.app/Contents/Developer"`.

```
brew install xcodegen
cd ios && xcodegen generate
cd ios/Packages/RecipeCore && swift test
xcodebuild test -project ios/RecipeBasket.xcodeproj -scheme RecipeBasket -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
cd api && npm install && npm test && npm run typecheck
cd api && npm run dev          # wrangler dev on http://localhost:8787 (secrets from api/.dev.vars)
cd api && npm run smoke -- ../fixtures/photos/chickpea-arrabbiata.jpg   # POST a real page to the dev server
cd api && npm run schema       # regenerate schema/extraction.schema.json from Zod
cd api && npm run eval         # extraction accuracy against fixtures/photos (both models; ≈ $1 per run)
```

`api/.dev.vars` (git-ignored, copy from `.dev.vars.example`) holds `ANTHROPIC_API_KEY` and `APP_KEY` for local dev and the eval.

The app reads the Worker URL and app key from `ios/Config/Secrets.xcconfig` (git-ignored; `xcodegen generate` copies `Secrets.example.xcconfig` if it is missing). Put the same `APP_KEY` there as in `api/.dev.vars`. In the simulator the app talks to `wrangler dev` on `http://localhost:8787`, so run `npm run dev` first. Put fixture pages in the simulator's photo library with `xcrun simctl addmedia "iPhone 17 Pro" fixtures/photos/*.jpg`. The VisionKit document camera only works on a real device.

Definition of done for any task: `swift test` in RecipeCore, the Xcode test run, and `npm test` in `api` all pass, with no new compiler warnings.

## Non-negotiable rules

1. **The model extracts; code calculates.** Scaling, rounding and formatting live in `RecipeCore` with tests. Never ask the model to do arithmetic or scale anything.
2. **Never ship the Anthropic API key in the app.** The app only calls the Worker. Don't log images or raw model output in production.
3. **One schema contract.** The Worker's Zod schema is the source of truth, exported to `schema/extraction.schema.json`. Swift `Codable` models must decode every file in `fixtures/expected/`; the Worker must validate the same files. Both test suites enforce this.
4. **Validate every model response with Zod** in the Worker before returning it. On failure retry once, then return a typed error.
5. **The user always reviews an extraction before it is saved.** Assume the model is sometimes wrong.
6. **Keep the book's units.** No unit conversion except promoting g→kg and ml→l at 1000. With dual units ("200g/7oz") the extraction takes the metric value.
7. **Fractions are fine.** ¼ of a tin is a valid output. Never round a count up to a whole item.
8. **`RecipeCore` stays pure.** No UI, persistence, EventKit or network imports.
9. **Export only adds reminders.** Never read back, update or delete existing reminders.
10. **Check current Apple, Anthropic and Cloudflare docs** rather than relying on memory. Record any deviation from this file in `docs/DECISIONS.md`.

## Working style

- One phase at a time. Start each phase in plan mode: files to create or change, public types and function signatures, tests to write. Wait for approval before coding.
- `RecipeCore` is test-first. Every bug found becomes a new fixture.
- Small commits with conventional commit messages at each green step.
- If the spec is ambiguous, contradictory or looks wrong, stop and ask rather than guessing.
- Signing and installing on a physical device need the user in Xcode; say when that step is reached rather than working around it.
