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
