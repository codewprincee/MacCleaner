# Changelog

All notable changes to MacCleaner will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-05-02

This is a near-complete rewrite of MacCleaner from a single-screen utility into a
full-featured open-source Mac cleaner. **Breaking change**: the deployment target
moves from macOS 13 to macOS 14 (Sonoma) to take advantage of `NavigationSplitView`,
Swift Charts, and `symbolEffect` APIs.

### Added

- **Production UI redesign** built on `NavigationSplitView` with a sidebar, hero
  Smart Clean view, onboarding flow, and dedicated Settings scene.
- **Menu bar mode** — quick access to scan / clean from the macOS menu bar.
- **App Uninstaller** — drag-and-drop removal of apps and their associated
  caches, preferences, and support files.
- **Large Files finder** — find files above a configurable size threshold.
- **Duplicate Files finder** — content-hash duplicate detection with safe
  preview before deletion.
- **Running-process detection** — warns before cleaning files belonging to a
  currently-running app.
- **Two-step destructive confirmation flow** — every destructive operation
  now requires a deliberate second confirmation.
- **Sparkle 2 auto-update integration** scaffolding (see "Notes" below).
- **Expanded cleanup categories**:
  - Browsers: Brave, Arc, Edge, Firefox, Vivaldi, Opera (in addition to
    Safari and Chrome).
  - Package managers: Cargo, Go, Conda, Bundler, Gradle, Maven, Composer
    (in addition to Homebrew, npm, pip, Yarn, CocoaPods).
  - Mail downloads, iOS device backups, diagnostic reports, Time Machine
    local snapshots.

### Changed

- **Shell command runner** is now an actor with strict argument quoting via
  `ShellCommandRunner.shellQuote`. All paths and untrusted strings are
  single-quoted before interpolation.
- **Pipe deadlock fix** — output from long-running shell commands is streamed
  via a `readabilityHandler` and a thread-safe collector instead of blocking
  on `pipe.readToEnd()`.
- **Command timeouts** — every shell invocation now has a configurable
  timeout that races process termination and cleanly kills (`SIGTERM` →
  `SIGKILL`) on expiry.

### Security

- **Patched shell injection** in cleanup category invocations by quoting all
  interpolated paths and removing direct string concatenation of
  user-controlled values into shell strings.
- **Bounded admin-elevation surface area** — privileged operations are now
  scoped to a fixed allowlist of cleanup categories; no user input is ever
  interpolated into the AppleScript / `osascript` layer.

### Developer experience

- New `Tests/MacCleanerTests` target with unit tests for `ByteFormatter`,
  `ShellCommandRunner.shellQuote`, and Docker size parsing.
- GitHub Actions CI on `macos-14` and `macos-15` (build, test, SwiftLint,
  SwiftFormat).
- Tagged release workflow that builds a universal binary, packages a DMG,
  and is wired (with TODOs) for code-signing, notarization, and Sparkle
  appcast generation.
- `.swiftlint.yml` and `.swiftformat` shipped with the repo.

### Notes

Sparkle 2 is wired in as `UpdateService.swift` and added as a SwiftPM
dependency, but the **`SUFeedURL`** and **`SUPublicEDKey`** Info.plist
entries must be set, and the EdDSA signing key generated, before the first
auto-update release.

## [1.0.0]

### Added

- Initial public release.
- 18 cleanup categories across 6 groups (File System, Xcode, Browsers,
  Package Managers, System (admin), Containers).
- Concurrent scanning across all categories.
- Native macOS admin password prompt via `osascript`.
- Disk usage bar with visual storage overview.
- Graceful degradation when optional tools (Docker, Homebrew, npm, ...) are
  not installed.

[Unreleased]: https://github.com/codewprincee/MacCleaner/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/codewprincee/MacCleaner/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/codewprincee/MacCleaner/releases/tag/v1.0.0
