# CLAUDE.md — Page & Plate

(The Xcode target, bundle id and StoreKit product ids are still `RecipeBasket` / `com.leonparsons.RecipeBasket`. Internal only; a user never sees them.)

Native iPhone and iPad app: photograph a recipe page → extract ingredients and yield → user confirms → scale to the portions wanted → add that recipe's ingredients to Apple Reminders (or share as text). A week planner puts recipes on days, each meal with its own portions, and exports the whole week at once.

Each recipe can be exported on its own, or a planned week in one go. The week export merges only lines whose ingredient name, unit and package size match exactly (quantities summed by code, rounded once) — nothing fuzzier. Duplicate items in Reminders are acceptable by design.

**Full product spec: `docs/SPEC.md`.** Read it before starting any phase. Build phases in order; don't start the next phase until the current one's acceptance criteria pass.

## Stack

- **App:** Swift 6 language mode, SwiftUI, iOS/iPadOS 17 minimum, universal target (iPhone and iPad).
- **Project generation:** XcodeGen from `ios/project.yml`. Never hand-edit `.pbxproj`; change `project.yml` and regenerate.
- **Persistence:** SwiftData, mirrored to the user's own private iCloud database (container `iCloud.com.leonparsons.RecipeBasket`). `AppModelContainer` migrates locally first, then opens mirrored. Schema versions live in `SchemaV1.swift` (frozen) and `AppSchemaVersions.swift`.
- **Capture:** VisionKit `VNDocumentCameraViewController` (wrapped for SwiftUI; auto-crops and flattens pages) plus `PhotosPicker` for existing photos. Resize long edge to ≤1568 px, JPEG quality ≈0.8 before upload.
- **Export:** EventKit (`requestFullAccessToReminders`) for Reminders; SwiftUI `ShareLink` for plain text.
- **Subscription:** StoreKit 2 (`Transaction.currentEntitlements` / `Transaction.updates`, `SubscriptionStoreView`); product ids in `Subscription/Products.swift`, mirrored in `ios/RecipeBasket.storekit` for the simulator (the scheme's StoreKit configuration). The free tier is `ScanAllowance` in RecipeCore plus a Keychain ledger.
- **Core logic:** local Swift package `RecipeCore` (models, scaling, rounding, fraction formatting, line formatting). Tests use Swift Testing.
- **API proxy:** Cloudflare Worker (TypeScript) + Hono + `@anthropic-ai/sdk` + Zod 4. Model name from env `ANTHROPIC_MODEL` (default `claude-sonnet-5`). API key is a Wrangler secret. Tests with Vitest.
- **Dependencies:** no third-party Swift packages without asking first.

## Layout

```
ios/project.yml               XcodeGen spec
ios/RecipeBasket/             App target: SwiftUI views, SwiftData models, VisionKit, EventKit, API client (Planner/ is the week view, Subscription/ the free tier and StoreKit)
ios/RecipeBasket/Brand.swift  Name, tagline, palette, display face and the app mark — the only place any of them live
ios/RecipeBasket/Models/      Recipe, PlannedMeal (SchemaV2), SchemaV1 frozen, AppSchemaVersions (migration plan)
ios/RecipeBasket/App/         AppModelContainer (the store), CloudAccount (iCloud status), AppConfiguration, DeviceIdentity
ios/Tools/RenderAppIcon.swift Re-renders the three 1024 app-icon PNGs from the same geometry as BrandMark
ios/RecipeBasket.storekit     Local StoreKit configuration: the two subscription plans at placeholder prices
ios/Packages/RecipeCore/      Pure Swift: Codable models, scaling, rounding, formatting (no SwiftUI/UIKit/EventKit/networking)
api/                          Cloudflare Worker: POST /extract, eval script, JSON Schema export
schema/extraction.schema.json Generated from the Worker's Zod schema; the contract between API and app
fixtures/scaling/             Scaling and formatting cases (JSON)
fixtures/planning/            Week boundaries (weeks.json) and week-export/ merge cases, one per file
fixtures/photos/              Real cookbook page photos for evals
fixtures/expected/            Hand-checked expected extractions for those photos
docs/SPEC.md                  Product spec and phases
docs/APPSTORE.md              App Store listing copy and the featuring nomination (limits checked by appstore-counts.py)
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
swift ios/Tools/RenderAppIcon.swift   # re-render the three 1024 app-icon PNGs after a change to the mark
python3 docs/appstore-counts.py       # check every App Store field against Apple's character limits
cd api && npm run eval         # extraction accuracy against fixtures/photos (both models; ≈ $1 per run)
cd api && npm run deploy       # after `npx wrangler login`, a KV namespace id in wrangler.jsonc and the two secrets (see docs/DECISIONS.md)
cd api && bash scripts/make-test-pki.sh   # regenerate the certificate chains entitlement.test.ts signs with (committed; they expire in 2046)
# StoreKit: only Xcode's own launch path syncs RecipeBasket.storekit to the simulator, so under `xcodebuild test`
# SKTestSession stays inert (error 3, purchases .notEntitled) and SubscriptionStoreTests record a known issue.
# To exercise the real purchase lifecycle, run the tests from Xcode (Cmd-U).
xcrun simctl privacy "iPhone 17 Pro" reset reminders com.leonparsons.RecipeBasket   # re-test the Reminders permission prompt
xcodebuild build -project ios/RecipeBasket.xcodeproj -scheme RecipeBasket -destination 'platform=iOS,id=00008150-00095D492140401C' -allowProvisioningUpdates   # Leon's iPhone
xcrun devicectl device install app --device 00008150-00095D492140401C <DerivedData>/Build/Products/Debug-iphoneos/RecipeBasket.app
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
9b. **The scan limits live in two places that must agree:** `ScanAllowance.trialScans` / `.weeklyScans` (app) and `FREE_SCANS` / `WEEKLY_SCANS` in `api/wrangler.jsonc` (Worker). The trial is **7 scans for the life of the device** — no window, no recovery. A subscription carries **25 in any rolling 7 days**, which is a real ceiling and is **never shown to the user**: not in the app, not in the Worker's error body. Tell someone when there is room again, never how many they had. The Worker verifies `x-entitlement` against Apple's certificate chain (Phase 8a) and the device with App Attest (Phase 8b). **When a request is attested the quota counts against the attested key, not `x-device-id`** — keep it that way, because the device id is client-chosen and counting against it is what made the trial free to farm. Still not closed: one real device can attest many keys, so don't call the trial unfarmable.
9d. **The household rules that are easy to soften by accident.** Joining a household **hides** the person's own *week* and never deletes it — their library keeps mirroring to their own private zone throughout, and leaving restores the week untouched. It does **not** hide their recipes: those flow into the household's catalogue, and into *every* household they belong to. Exactly **one plan is on display**; Settings is the only place it changes, and once someone hosts a household that household *is* their own plan. **Hosting needs an active subscription** (membership is free). Leaving one household must take only that household's rows: `SharedStore.empty(_:household:)`, never the whole store, which is for signing out of iCloud.

9e. **Six things in the household code that look like details and are not.** The last two are what Phase 11b got wrong, and between them they broke every edit on a device while every test passed.
- **A household is `(zoneName, ownerName)`, never `zoneName` alone.** `SharedWeekZone.zoneName` is the constant `"SharedPlan"` in every owner's database, so anything keyed on it merges two households into one. Rows carry `Household.id`.
- **The household store is a cache, and `SharedStore.generation` names the store file *and* both engine state files.** Discarding rows while keeping a `CKSyncEngine`'s change token means the store never refills — the household goes blank for good, with no error anywhere. Bump the one constant; never rename the store on its own. (Renaming a cache is a legitimate migration; it is not legitimate for the app's own store, where `SchemaV1` is frozen.)
- **`SharedPlanContext.projectLibrary` must stay idempotent, and all-or-nothing.** `ModelContext.didSave` is one notification for the whole app, so writing to the household store wakes the watcher that writes to the household store: skipping a recipe whose projected row compares equal is the only thing stopping an endless loop. And the local row is later read as "this household has been told" while the deletion journal is emptied by draining it, so a pass that can only half-send must not run at all.
- **A recipe belongs to its author and only stops being projected — it is never deleted from their library.** An `authorID` the app cannot attribute is treated as *somebody else's*, never as this device's, and is never pruned.
- **One store, one `ModelContext`: the household store is reached through `container.mainContext` and nothing else.** The views query `mainContext`, so an editor or an engine holding a context of its own is handed objects it does not own — a mutation gets saved through a context with nothing pending, a reindex is applied to second copies of the rows on screen, and a delete removes an object out from under a live reference. It presents as "the edit didn't travel", "it's still there when I go back in", and a crash, with no error anywhere. Phase 11b had **four** contexts over one container and produced all three.
- **A record sent to CloudKit is built from the row, never constructed fresh.** `CKRecord(recordType:recordID:)` carries no `recordChangeTag`, and CloudKit refuses to save over an existing record without one — so a fresh record is accepted the first time and refused for ever after. `HouseholdRecords` keeps each row's `systemFields` and builds on them, and a `serverRecordChanged` refusal must **adopt the server's record and stage the save again**: last-writer-wins only happens if the loser is re-sent. Logging that error and dropping it is what made every household edit after the first one vanish, in both directions.
- **CloudKit will not tell you anybody's name — not even the user's own.** `CKUserIdentity.nameComponents` needs the user-discoverability permission, and iOS 17 removed that permission and every `discoverUserIdentity` API ("No longer supported", per the SDK header). So `CKShare.Participant` names are nil on every build this app can ship, and any feature that names a person must be fed by a name that person **typed** — `HouseholdAuthor.name`, published as a `SharedMember` record beside their recipes. Do not "fix" a blank name by re-reading the share; there is nothing there.
9c. **Every `@Model` property must stay CloudKit-legal.** No `@Attribute(.unique)`, a default value on every non-optional attribute, and every relationship optional. Break one and the store silently stops syncing — `CloudKitSchemaTests` catches it, including by loading a real mirrored container. Read a to-many relationship through its accessor (`orderedPages`, `meals`), not the optional property.
10. **Check current Apple, Anthropic and Cloudflare docs** rather than relying on memory. Record any deviation from this file in `docs/DECISIONS.md`.

## Working style

- One phase at a time. Start each phase in plan mode: files to create or change, public types and function signatures, tests to write. Wait for approval before coding.
- `RecipeCore` is test-first. Every bug found becomes a new fixture.
- Small commits with conventional commit messages at each green step.
- If the spec is ambiguous, contradictory or looks wrong, stop and ask rather than guessing.
- Signing and installing on a physical device need the user in Xcode; say when that step is reached rather than working around it.
