# Brewy — Claude Project Context

Brewy is a native macOS GUI for managing Homebrew packages, written in Swift/SwiftUI. It lets users browse, search, install, upgrade, pin, and uninstall formulae and casks without opening Terminal. The project is open source (GPL-3.0-only) and lives at https://github.com/p-linnane/brewy.

## Project overview

- **Platform:** macOS 15.0+ (Apple Silicon), built with Xcode 16+
- **Language:** Swift, SwiftUI (100%)
- **Architecture:** MVVM using `@Observable` and SwiftUI Environment injection
- **Only external dependency:** Sparkle via Swift Package Manager for auto-updates
- **Bundle ID:** `io.linnane.brewy`
- **License:** GPL-3.0-only

## Repository structure

```
Brewy/
├── Brewy/
│   ├── BrewyApp.swift              # @main entry, WindowGroup, MenuBarExtra, Sparkle updater
│   ├── Info.plist                   # Sparkle feed URL + EdDSA public key
│   ├── Assets.xcassets/             # App icon, accent color
│   ├── Models/
│   │   ├── BrewService.swift        # @Observable service: state, caching, all brew CLI interactions
│   │   ├── PackageModel.swift       # Data models + Brew JSON v2 Codable types + appcast parser
│   │   ├── CommandRunner.swift      # Process execution with timeout, cancellation, thread-safe pipe reading
│   │   └── TapHealthChecker.swift   # Async GitHub API tap health detection (archived, moved, missing)
│   └── Views/
│       ├── ContentView.swift        # NavigationSplitView (3-column), toolbar, state management
│       ├── SidebarView.swift        # Category list (Installed, Formulae, Casks, Outdated, Pinned, Leaves, Taps, Discover, Maintenance)
│       ├── PackageListView.swift    # Package list with search, selection toggles for bulk upgrade
│       ├── PackageDetailView.swift  # Detail pane: info, dependencies, reverse deps, actions, FlowLayout for tags
│       ├── DiscoverView.swift       # Search all of Homebrew (formulae + casks)
│       ├── MaintenanceView.swift    # brew doctor, cleanup, autoremove, cache management
│       ├── SettingsView.swift       # Brew path, auto-refresh interval, theme
│       ├── TapListView.swift        # Add/remove taps
│       └── WhatsNewView.swift       # Release notes from Sparkle appcast
├── BrewyTests/
│   ├── BrewServiceTests.swift       # Derived state, reverse deps, leaves, pinned, category routing, merge logic
│   └── PackageModelTests.swift      # JSON parsing, model equality, config parsing, appcast parsing
├── Brewy.xcodeproj/
├── .github/
│   ├── workflows/
│   │   ├── build.yml                # PR tests: Thread Sanitizer + Address Sanitizer, coverage
│   │   ├── release.yml              # Manual dispatch: archive, sign, notarize, Sparkle EdDSA, appcast, GitHub release, auto-bump Homebrew cask
│   │   ├── swiftlint.yml            # Lint with --strict on PRs
│   │   ├── codeql.yml               # Security analysis
│   │   ├── pr-title.yml             # PR title validation
│   │   └── zizmor.yml               # GitHub Actions security scanning
│   ├── appcast-template.xml         # Sparkle appcast template with envsubst placeholders
│   ├── format-release-notes.py      # Formats GitHub auto-generated release notes (markdown + HTML)
│   └── dependabot.yml               # Dependency updates
├── .swiftlint.yml                   # 37 opt-in rules, line length 150/200, function body 60/100
├── .gitignore
├── LICENSE
└── README.md
```

## Architecture details

### BrewService (@Observable, @MainActor)

The central service object that holds all app state and orchestrates brew CLI calls. Injected into the view hierarchy via `.environment(brewService)`.

**State properties:** `installedFormulae`, `installedCasks`, `outdatedPackages`, `installedTaps`, `searchResults`, `isLoading`, `isPerformingAction`, `actionOutput`, `lastError`, `lastUpdated`, `tapHealthStatuses`

**Derived state** (recomputed on `didSet` of formulae/casks): `allInstalled`, `installedNames`, `reverseDependencies`

**Computed properties:** `pinnedPackages`, `leavesPackages`

**Key methods:**
- `refresh()` — parallel fetch of formulae, casks, and outdated; merges outdated status; saves cache
- `search(query:)` — parallel `brew search --formula` + `brew search --cask`
- `install/uninstall/upgrade/pin/unpin(package:)` — single package operations with `--cask` flag when needed
- `upgradeAll()`, `upgradeSelected(packages:)` — bulk upgrades (formulae and casks separately)
- `doctor()`, `cleanup()`, `removeOrphans()`, `purgeCache()`, `cacheSize()` — maintenance
- `addTap/removeTap(name:)` — tap management
- `checkTapHealth()` — async GitHub API check for archived, moved, or missing taps (runs on refresh)
- `migrateTap(from:to:)` — untap old → tap new for moved repositories
- `config()` — parses `brew config` output
- `info(for:)` — cached `brew info` output

**Caching:** JSON serialization to `~/Library/Application Support/Brewy/packageCache.json` (packages) and `tapHealthCache.json` (tap health statuses with 24-hour TTL). Both loaded on app start, saved after each refresh.

### CommandRunner

Static enum that executes `Process` (brew CLI) with:
- Configurable timeout (default 5 minutes)
- Thread-safe stderr reading via `LockedData` (NSLock-backed accumulator)
- DispatchWorkItem-based timeout termination
- Brew path resolution: preferred path → `/usr/local/bin/brew` fallback

### TapHealthChecker

Async utility that checks the health of installed taps via the GitHub API:
- Uses `URLSession` with a no-redirect delegate to detect HTTP 301 (moved) and 404 (deleted) responses
- Detects archived repositories via the `archived` flag in GitHub API JSON
- Resolves redirect URLs for moved repositories to capture the new `html_url`
- Results cached as `TapHealthStatus` with a 24-hour TTL; only stale taps are re-checked

### Data models (PackageModel.swift)

- `BrewPackage` — Identifiable, Hashable, Codable. ID-based equality. `displayVersion` shows `installed → latest` when outdated.
- `BrewTap` — tap metadata (name, remote, official status, formula/cask counts)
- `SidebarCategory` — 9-case enum with SF Symbol icons
- `AppcastRelease` — parsed from Sparkle XML feed
- `TapHealthStatus` — Codable model with `Status` enum (healthy, archived, moved, notFound, unknown), `movedTo` URL, `lastChecked` date, 24-hour staleness TTL; includes static helpers for parsing GitHub repo URLs and deriving tap names
- `BrewConfig` — parsed from `brew config` key-value output
- JSON response types: `BrewInfoResponse`, `FormulaJSON`, `CaskJSON`, `BrewOutdatedResponse`, `OutdatedFormulaJSON`, `OutdatedCaskJSON`, `TapJSON`

### Brew CLI commands used

```
brew info --installed --json=v2              # Installed formulae
brew info --installed --cask --json=v2       # Installed casks
brew outdated --json=v2                      # Outdated packages
brew tap-info --json=v1 --installed          # Installed taps
brew search --formula/--cask <query>         # Search
brew install/uninstall/upgrade [--cask] PKG  # Package operations
brew pin/unpin PKG                           # Pin management
brew doctor                                  # Diagnostics
brew cleanup --prune=all [-s]                # Cleanup / purge cache
brew autoremove                              # Remove orphans
brew update                                  # Update Homebrew itself
brew config                                  # Configuration info
brew --cache                                 # Cache path
brew tap/untap NAME                          # Tap management
```

## App features

- NavigationSplitView (3-column) with sidebar categories
- MenuBarExtra showing outdated package count (mug icon)
- Keyboard shortcuts: Cmd+R (refresh), Cmd+U (upgrade all)
- Bulk upgrade: select specific outdated packages to upgrade
- Reverse dependency computation for installed packages
- Leaves detection (formulae with no reverse dependencies)
- Configurable brew path, auto-refresh interval, theme (light/dark/system)
- Tap health monitoring: detects archived, moved, and missing tap repositories via GitHub API
- Tap migration: one-click migrate to a tap's new URL when it has moved
- "What's New" view parsing Sparkle appcast XML
- Sparkle auto-updates with EdDSA signing

## Testing

- Framework: Swift Testing (`@Suite`, `@Test` macros)
- ~50+ test cases across two files
- Tests cover: derived state, reverse deps, leaves, pinned filtering, category routing, outdated merge logic, all JSON parsing, model equality/hashing, config parsing, appcast XML parsing, tap health status (codable, GitHub URL parsing, staleness)
- CI runs both Thread Sanitizer and Address Sanitizer
- Code coverage reported via `xccov`

## CI/CD pipeline

**PR checks:** SwiftLint (strict), Thread Sanitizer tests, Address Sanitizer tests, CodeQL, PR title validation, zizmor (Actions security)

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

Common types used in this project: `feat`, `fix`, `refactor`, `docs`, `ci`, `chore`

PRs are squash-merged with the PR number appended, e.g. `feat: add test suite with CI, sanitizers, and code coverage (#38)`.

## Code style and conventions

- SwiftLint with 37 opt-in rules enabled (see `.swiftlint.yml`)
- Line length: warning at 150, error at 200
- Function body length: warning at 60, error at 100
- `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` in CI
- `SWIFT_STRICT_CONCURRENCY=complete` (Swift 6 strict concurrency checking)
- `@MainActor` isolation on BrewService
- Structured concurrency: `async let` for parallel fetches, `Task.detached` for JSON parsing
- Logging via `OSLog` (`Logger(subsystem: "io.linnane.brewy", category: ...)`)
- MARK comments for code organization
- Errors are `LocalizedError` with descriptive messages

## Key design decisions

- BrewService acts as both service layer and state container (pragmatic for a focused app)
- All brew interactions go through CommandRunner (single execution path)
- JSON v2 API used for structured data; text output parsed for search results and config
- Cache enables instant app launch with stale data, then background refresh
- Reverse dependencies computed eagerly on state change (O(n) per refresh, avoids repeated computation)
- Search results tagged with `isInstalled` by cross-referencing `installedNames` set
