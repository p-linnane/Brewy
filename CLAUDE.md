# Brewy — Claude Project Context

Brewy is a native macOS GUI for managing Homebrew packages, written in Swift/SwiftUI. It lets users browse, search, install, upgrade, pin, and uninstall formulae and casks without opening Terminal. The project is open source (AGPL-3.0-only) and lives at https://github.com/starhaven-io/Brewy.

## Project overview

- **Platform:** macOS 15.0+ (Apple Silicon), built with Xcode 16+
- **Language:** Swift, SwiftUI (100%)
- **Architecture:** MVVM using `@Observable` and SwiftUI Environment injection
- **Only external dependency:** Sparkle via Swift Package Manager for auto-updates
- **Bundle ID:** `io.linnane.brewy`
- **License:** AGPL-3.0-only

## Repository structure

```
Brewy/
├── Brewy/
│   ├── BrewyApp.swift                      # @main entry, WindowGroup, MenuBarExtra, Sparkle updater
│   ├── Info.plist                           # Sparkle feed URL + EdDSA public key
│   ├── Assets.xcassets/                     # App icon, accent color
│   ├── Models/
│   │   ├── BrewService.swift               # @Observable service: core state, caching, derived state, CLI orchestration
│   │   ├── BrewService+Fetching.swift      # Installed package and outdated package fetching
│   │   ├── BrewService+Actions.swift       # Package action helpers (install, uninstall, upgrade, pin, etc.)
│   │   ├── BrewService+PackageDetail.swift # Single-package detail fetching
│   │   ├── BrewService+History.swift       # Action history recording, persistence, retry, outdated merge helper
│   │   ├── BrewService+Groups.swift        # User-created package group CRUD and persistence
│   │   ├── BrewService+DryRun.swift        # Dry-run previews for autoremove and cleanup
│   │   ├── BrewJSONTypes.swift             # Brew JSON v2 Codable response types (extracted from PackageModel)
│   │   ├── PackageModel.swift              # Data models: BrewPackage, BrewTap, SidebarCategory, PackageGroup, ActionHistoryEntry, BrewServiceItem, BrewConfig, appcast parser
│   │   ├── CommandRunner.swift             # Process execution with timeout, cancellation, thread-safe pipe reading, CommandRunning protocol
│   │   ├── MasService.swift                # Mac App Store integration via mas CLI (list, outdated, install)
│   │   ├── ServicesService.swift           # Homebrew services management (fetch, start, stop, restart, cleanup)
│   │   └── TapHealthChecker.swift          # Async GitHub API tap health detection (archived, moved, missing)
│   └── Views/
│       ├── ContentView.swift               # NavigationSplitView (3-column), toolbar, state management
│       ├── SidebarView.swift               # Category list (13 categories, see SidebarCategory enum)
│       ├── PackageListView.swift           # Package list with search, selection toggles for bulk upgrade
│       ├── PackageDetailView.swift         # Detail pane: info, dependencies, reverse deps, actions
│       ├── DiscoverView.swift              # Search all of Homebrew (formulae + casks)
│       ├── GroupsView.swift                # Custom package groups with CRUD UI
│       ├── HistoryView.swift               # Action history with review and retry
│       ├── ServicesView.swift              # Homebrew services control UI
│       ├── MasSetupView.swift              # Mac App Store setup/configuration UI
│       ├── MaintenanceView.swift           # brew doctor, cleanup, autoremove, cache management
│       ├── DryRunConfirmationSheet.swift   # Preview modal for cleanup/autoremove operations
│       ├── SharedViews.swift               # Reusable components: FlowLayout, ConsoleOutput, ActionOverlay
│       ├── SettingsView.swift              # Brew path, auto-refresh interval, theme
│       ├── TapListView.swift               # Add/remove taps
│       └── WhatsNewView.swift              # Release notes from Sparkle appcast
├── BrewyTests/
│   ├── TestHelpers.swift                   # Shared test utilities (MockCommandRunner, etc.)
│   ├── BrewServiceTests.swift              # Core service logic: derived state, reverse deps, leaves, category routing
│   ├── BrewServiceAsyncTests.swift         # Async tests: refresh, search, bulk upgrade, actions
│   ├── BrewServiceDetailTests.swift        # Maintenance, dry-run, info caching, tap management, retry, error handling
│   ├── CommandRunnerTests.swift            # CommandRunner process execution + MockCommandRunner behavior
│   ├── PackageModelTests.swift             # Package model JSON parsing, equality, hashing
│   ├── TapAndConfigTests.swift             # Tap health, GitHub URL parsing, appcast parsing, config parsing
│   ├── GroupsAndMasTests.swift             # Package groups, Mac App Store parsing
│   ├── HistoryTests.swift                  # Action history recording and retry
│   ├── ServicesTests.swift                 # Services parsing and integration
│   └── JSONAndServicesTests.swift          # JSON parsing edge cases and services
├── BrewyUITests/
│   └── SidebarNavigationUITests.swift      # UI tests for sidebar navigation
├── Brewy.xcodeproj/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                          # Unified PR checks: dynamic matrix runs lint, TSAN, ASAN, CodeQL, zizmor, Conventional Commits
│   │   ├── release.yml                     # Manual dispatch: archive, sign, notarize, Sparkle EdDSA, appcast, GitHub release, auto-bump Homebrew cask
│   │   ├── codeql.yml                      # Scheduled CodeQL analysis (on-push/scheduled, separate from PR matrix)
│   │   ├── pinprick-audit.yml              # Audits dependency permissions via pinprick
│   │   └── zizmor.yml                      # Scheduled GitHub Actions security scanning
│   ├── appcast-template.xml                # Sparkle appcast template with envsubst placeholders
│   ├── format-release-notes.py             # Formats GitHub auto-generated release notes (markdown + HTML)
│   └── dependabot.yml                      # Dependency updates (Swift dependencies)
├── justfile                                # Just command runner for local development (check, lint, test, audit)
├── .swiftlint.yml                          # 60 opt-in rules, line length 150/200, function body 60/100
├── .gitignore
├── LICENSE
└── README.md
```

## Architecture details

### BrewService (@Observable, @MainActor)

The central service object that holds all app state and orchestrates brew CLI calls. Injected into the view hierarchy via `.environment(brewService)`. Split across multiple extension files for single-responsibility organization.

**State properties:** `installedFormulae`, `installedCasks`, `installedMasApps`, `isMasAvailable`, `outdatedPackages`, `installedTaps`, `searchResults`, `isLoading`, `isPerformingAction`, `actionOutput`, `lastError`, `lastUpdated`, `tapHealthStatuses`, `packageGroups`, `actionHistory`

**Derived state** (recomputed via `invalidateDerivedState()` on package changes): `allInstalled`, `installedNames`, `reverseDependencies`, `leavesPackages`, `pinnedPackages`

**Key methods:**
- `refresh()` — parallel fetch of formulae, casks, mas apps, and outdated; merges outdated status; saves cache
- `search(query:)` — parallel `brew search --formula` + `brew search --cask`
- `install/uninstall/upgrade/pin/unpin/reinstall/fetch/link/unlink(package:)` — single package operations with `--cask` flag when needed
- `upgradeAll()`, `upgradeSelected(packages:)` — bulk upgrades (formulae and casks separately)
- `doctor()`, `cleanup()`, `removeOrphans()`, `purgeCache()`, `cacheSize()` — maintenance
- `dryRunAutoremove()`, `dryRunCleanup()` — preview cleanup operations before executing
- `addTap/removeTap(name:)`, `migrateTap(from:to:)` — tap management
- `checkTapHealth()` — async GitHub API check for archived, moved, or missing taps (runs on refresh)
- `createGroup/deleteGroup/updateGroup/addToGroup/removeFromGroup/packages(in:)` — package group CRUD
- `recordAction/retryAction/clearHistory/loadHistory` — action history management
- `fetchServices/startService/stopService/restartService/cleanupServices` — Homebrew services
- `fetchInstalledMasApps/fetchOutdatedMasApps` — Mac App Store integration
- `fetchPackageDetail(for:)` — cached single-package detail fetch
- `config()` — parses `brew config` output
- `info(for:)` — cached `brew info` output

**Caching:** JSON serialization to `~/Library/Application Support/Brewy/`:
- `packageCache.json` — packages (formulae, casks, mas apps, outdated, taps). Tagged with `cacheSchemaVersion`; a version mismatch or decode failure deletes the file so the app doesn't silently launch into empty state after a schema change.
- `tapHealthCache.json` — tap health statuses with 24-hour TTL
- `packageGroups.json` — user-created package groups
- `actionHistory.json` — action history (max 100 entries)

### CommandRunner

Static enum that executes `Process` (brew CLI and other executables) with:
- `CommandRunning` protocol for dependency injection and testability
- Configurable timeout (default 5 minutes) with sub-second precision preserved
- Parallel stdout/stderr drain via dedicated `PipeReader` instances so large output on either stream can't deadlock the subprocess
- Two-stage timeout termination: SIGTERM first, then SIGKILL after a 3s grace period; `CommandResult.didTimeOut` distinguishes timeouts from other failures
- `LockedData` (NSLock-backed) and `LockedFlag` accumulators for thread-safe output collection
- Brew path resolution: preferred path → `/usr/local/bin/brew` fallback
- `runExecutable(_:arguments:)` — generic executable runner for external tools (mas, sudo, du)
- `resolvedMasPath()` — path resolution for Mac App Store CLI tool
- PATH augmentation to include brew's bin and sbin directories

### MasService

Mac App Store integration via the `mas` CLI:
- `MasParser` parses `mas list` and `mas outdated` output into `BrewPackage` models with `.mas` source
- Unique IDs prefixed with `mas-` to avoid collisions with brew packages
- `fetchInstalledMasApps()` and `fetchOutdatedMasApps()` in BrewService extensions

### ServicesService

Homebrew services management:
- `ServicesParser` decodes `brew services info --all --json` or `brew services list --json` output
- Start, stop, restart individual services (with optional sudo)
- Cleanup stale services via `brew services cleanup`
- `BrewServiceItem` model with detailed service info (name, status, PID, user, log paths)

### TapHealthChecker

Async utility that checks the health of installed taps via the GitHub API:
- Uses `URLSession` with a no-redirect delegate to detect HTTP 301 (moved) and 404 (deleted) responses
- Detects archived repositories via the `archived` flag in GitHub API JSON
- Resolves redirect URLs for moved repositories to capture the new `html_url`
- Results cached as `TapHealthStatus` with a 24-hour TTL; only stale taps are re-checked

### Data models (PackageModel.swift)

- `PackageSource` — enum: `.formula`, `.cask`, `.mas`
- `BrewPackage` — Identifiable, Hashable, Codable. ID-based equality. `source` field determines type. `displayVersion` shows `installed → latest` when outdated.
- `BrewTap` — tap metadata (name, remote, official status, formula/cask counts)
- `SidebarCategory` — 13-case enum with SF Symbol icons (Installed, Formulae, Casks, Mac App Store, Outdated, Pinned, Leaves, Taps, Services, Groups, History, Discover, Maintenance)
- `PackageGroup` — user-created groups for organizing packages (Identifiable, Codable, Hashable)
- `ActionHistoryEntry` — records each brew action (command, arguments, status, output, timestamp) with retry support
- `BrewServiceItem` — Homebrew service info (name, running/loaded status, PID, user, log paths) with JSON CodingKeys
- `AppcastRelease` — parsed from Sparkle XML feed
- `TapHealthStatus` — Codable model with `Status` enum (healthy, archived, moved, notFound, unknown), `movedTo` URL, `lastChecked` date, 24-hour staleness TTL; includes static helpers for parsing GitHub repo URLs and deriving tap names
- `BrewConfig` — parsed from `brew config` key-value output

### Brew JSON types (BrewJSONTypes.swift)

- `BrewInfoResponse`, `FormulaJSON`, `CaskJSON` — Brew JSON v2 info response types
- `BrewOutdatedResponse`, `OutdatedFormulaJSON`, `OutdatedCaskJSON` — outdated package response types
- `TapJSON` — tap info response type

### Brew CLI commands used

```
brew info --installed --json=v2              # Installed formulae
brew info --installed --cask --json=v2       # Installed casks
brew info [--cask] --json=v2 <name>          # Single package detail
brew outdated --json=v2                      # Outdated packages
brew tap-info --json=v1 --installed          # Installed taps
brew search --formula/--cask <query>         # Search
brew install/uninstall/upgrade [--cask] PKG  # Package operations
brew reinstall/fetch/link/unlink PKG         # Additional package operations
brew pin/unpin PKG                           # Pin management
brew doctor                                  # Diagnostics
brew cleanup --prune=all [-s] [--dry-run]    # Cleanup / purge cache (with optional preview)
brew autoremove [--dry-run]                  # Remove orphans (with optional preview)
brew update                                  # Update Homebrew itself
brew config                                  # Configuration info
brew --cache                                 # Cache path
brew tap/untap NAME                          # Tap management
brew services info --all --json              # Services info
brew services list --json                    # Services list
brew services start/stop/restart NAME        # Service control
brew services cleanup                        # Clean up stale services
mas list                                     # Installed Mac App Store apps
mas outdated                                 # Outdated Mac App Store apps
mas install ID                               # Install Mac App Store app
```

## App features

- NavigationSplitView (3-column) with 13 sidebar categories
- MenuBarExtra showing outdated package count (mug icon)
- Keyboard shortcuts: Cmd+R (refresh), Cmd+U (upgrade all)
- Bulk upgrade: select specific outdated packages to upgrade
- Reverse dependency computation for installed packages
- Leaves detection (formulae with no reverse dependencies)
- Mac App Store integration via `mas` CLI (browse installed apps, check for updates)
- Homebrew services management (start, stop, restart, cleanup)
- Custom package groups: create, edit, delete groups and organize packages into them
- Action history: records all brew actions with retry support for failed commands
- Dry-run previews for autoremove and cleanup before executing
- Configurable brew path, auto-refresh interval, theme (light/dark/system)
- Tap health monitoring: detects archived, moved, and missing tap repositories via GitHub API
- Tap migration: one-click migrate to a tap's new URL when it has moved
- "What's New" view parsing Sparkle appcast XML
- Sparkle auto-updates with EdDSA signing

## Testing

- Framework: Swift Testing (`@Suite`, `@Test` macros)
- ~200 test cases across 11 test files (10 unit test files + 1 test helpers)
- `MockCommandRunner` and shared test helpers in `TestHelpers.swift`
- Tests cover: derived state, reverse deps, leaves, pinned filtering, category routing, outdated merge logic, all JSON parsing, model equality/hashing, config parsing, appcast XML parsing, tap health status, package groups, Mac App Store parsing, action history, services, dry-run, retry, error handling, async refresh/search/upgrade flows, real-subprocess CommandRunner behavior (stdout/stderr drain, timeout, missing executable)
- UI tests: sidebar navigation
- CI runs both Thread Sanitizer and Address Sanitizer
- Code coverage reported via `xccov`

## CI/CD pipeline

**PR checks:** A single `ci.yml` workflow generates a dynamic matrix based on changed paths: Conventional Commits (always), Lint + TSAN + ASAN (Swift changes), CodeQL (source-tree changes), zizmor (workflow changes). A final `conclusion` job gates merge on the matrix result. Edited PR events get their own per-run concurrency group so body/title edits don't cancel in-flight tests.

**Release (manual dispatch):**
1. Create git tag
2. Archive with Developer ID code signing
3. Export and zip
4. Generate build provenance attestation
5. Notarize with Apple + staple
6. Sign with Sparkle EdDSA key
7. Create GitHub release with auto-generated + formatted notes
8. Update appcast.xml on the `appcast` branch
9. Auto-bump the Homebrew cask via `brew bump --open-pr --casks brewy`

## Commit conventions

Conventional Commits format: `type(scope): description`

Common types: `feat`, `fix`, `refactor`, `docs`, `ci`, `chore`

All commits must:
- Use `git commit -s` for DCO sign-off
- Include a `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer when authored with Claude (the local pre-commit hook checks for this)

PRs are squash-merged with the PR number appended, e.g. `feat: add test suite with CI, sanitizers, and code coverage (#38)`.

## Git workflow

- Never commit directly to main — always create a feature branch and open a PR
- Version bumps follow the pattern: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj`, commit as `chore: bump version to X.Y.Z (build N)`, open a PR
- Releases are cut by triggering the Release workflow dispatch after the version bump PR is merged — the workflow reads `MARKETING_VERSION` from the Xcode project and creates the tag automatically

## PR conventions

- PR descriptions should contain only a summary of the changes — no test plan sections, no bot attribution, no "Generated with Claude Code" footers

## Code style and conventions

- SwiftLint with 64 opt-in rules enabled (see `.swiftlint.yml`)
- Line length: warning at 150, error at 200
- Function body length: warning at 60, error at 100
- `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` in CI
- `SWIFT_STRICT_CONCURRENCY=complete` (Swift 6 strict concurrency checking)
- `@MainActor` isolation on BrewService
- `CommandRunning` protocol for dependency injection (enables `MockCommandRunner` in tests)
- Structured concurrency: `async let` for parallel fetches, `Task.detached` for JSON parsing
- Logging via `OSLog` (`Logger(subsystem: "io.linnane.brewy", category: ...)`)
- MARK comments for code organization
- Errors are `LocalizedError` with descriptive messages

## Key design decisions

- BrewService acts as both service layer and state container, split into focused extensions for maintainability
- All brew interactions go through CommandRunner via the `CommandRunning` protocol (single execution path, testable)
- JSON v2 API used for structured data; text output parsed for search results and config
- Cache enables instant app launch with stale data, then background refresh
- Derived state (reverse deps, leaves, pinned) computed eagerly via `invalidateDerivedState()`, with batch updates to avoid redundant recomputation
- Search results tagged with `isInstalled` by cross-referencing `installedNames` set
- Mac App Store packages use `mas-` prefixed IDs to avoid collisions with brew package IDs
- Action history capped at 100 entries with automatic pruning
