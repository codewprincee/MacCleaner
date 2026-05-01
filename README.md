<div align="center">

# MacCleaner

**The free, open-source Mac cleaner that respects your privacy.**

Reclaim disk space. Uninstall apps cleanly. Find duplicate files. All locally, no telemetry, no account, no paywall.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License MIT](https://img.shields.io/badge/License-MIT-green) ![CI](https://img.shields.io/github/actions/workflow/status/codewprincee/MacCleaner/ci.yml?branch=main)

[Download](https://github.com/codewprincee/MacCleaner/releases/latest) · [Contribute](CONTRIBUTING.md) · [Report a bug](https://github.com/codewprincee/MacCleaner/issues/new?template=bug_report.yml) · [Discussions](https://github.com/codewprincee/MacCleaner/discussions)

</div>

---

## Features

### Smart Clean
A unified scan across **30+ cleanup categories** with a hero "ready to free" number, donut chart breakdown, and one-click cleaning. Every destructive action is gated behind a confirmation sheet.

### App Uninstaller
Drag any `.app` onto the target. MacCleaner finds every leftover across **14 categories** — Application Support, Caches, Preferences, Logs, Saved State, LaunchAgents/Daemons, Group Containers, Sandbox Containers, Cookies, WebKit data, Crash Reports, Application Scripts, and the main bundle (which goes to Trash, not unlinked).

### Large Files Finder
Walks your home directory for files over a configurable threshold (50 MB → 1 GB+). Categorized as Videos, Archives, Disk Images, Installers, Documents, Backups. Move-to-Trash with a 5-second Undo window.

### Duplicate Files Finder
Two-pass detection: bucket files by size, then SHA-256 their contents in 1 MB streaming chunks. Handles 100k+ files with bounded memory. Auto-select strategies: keep newest / oldest / shortest path. Always Trash, never permadelete.

### Menu Bar Mode
A live disk-pressure indicator in your menu bar. Click for a 320pt popover with the reclaimable hero number, Quick Clean button, and direct shortcuts to Empty Trash, Flush DNS, and the main app. Notifies you on low → critical disk transitions, never spam.

### Cleanup Categories

| Group | Categories |
|---|---|
| **File System** | User Caches · System Logs · Temp Files · Trash · Old Downloads (>30 days) · Mail Downloads · iOS Device Backups · Screen Recordings |
| **Xcode** | Derived Data · iOS Device Support · iOS Simulators · Archives |
| **Browsers** | Safari · Chrome · Brave · Arc · Edge · Firefox · Vivaldi · Opera (each refuses to clean while the browser is running) |
| **Package Managers** | Homebrew · npm · pip · Yarn · CocoaPods · Cargo · Go modules · Conda · Bundler · Gradle · Maven · Composer |
| **System** (admin) | System Caches · DNS Cache · Diagnostic Reports · Crash Reports · Time Machine Local Snapshots |
| **Containers** | Docker (images, volumes, build cache) |

## Privacy

MacCleaner is built around an explicit **no-telemetry pledge**:

- **No analytics, no tracking, no account.** The app never makes a network request unless you click "Check for Updates…".
- **No telemetry of what you clean.** Categories, paths, sizes — none of it leaves your machine.
- **What we don't touch:** Documents, Photos, Mail messages (only sandboxed Mail *attachments* on request), Music, system files SIP would refuse anyway.
- **Open source under MIT** — every line of code is auditable.

## Why MacCleaner?

|  | MacCleaner | CleanMyMac X | OnyX | AppCleaner |
|---|---|---|---|---|
| Free | ✅ | ❌ ($40/yr) | ✅ | ✅ |
| Open source | ✅ | ❌ | ❌ | ❌ |
| No telemetry | ✅ | ❌ | ✅ | ✅ |
| App uninstaller with leftover detection | ✅ | ✅ | ❌ | ✅ |
| Large file finder | ✅ | ✅ | ❌ | ❌ |
| Duplicate finder | ✅ | ✅ | ❌ | ❌ |
| Menu bar mode | ✅ | ✅ | ❌ | ❌ |
| Native SwiftUI | ✅ | ❌ | ❌ | ❌ |

## Install

### Download a release (recommended)

Grab the latest `.dmg` from the [Releases page](https://github.com/codewprincee/MacCleaner/releases/latest), open it, and drag MacCleaner to `/Applications`.

### Build from source

Requires **macOS 14+**, **Xcode 15+**, **Swift 5.9+**.

```bash
git clone https://github.com/codewprincee/MacCleaner.git
cd MacCleaner
./install.sh
```

The script builds a release binary, embeds frameworks, ad-hoc signs the bundle, and installs to `/Applications/MacCleaner.app`.

### Open in Xcode

```bash
open Package.swift
```

## Architecture

```
Sources/MacCleaner/
├── MacCleanerApp.swift            # SwiftUI entry point + Settings + Onboarding gate
├── MenuBar/                       # NSStatusItem + popover + AppDelegate
├── Models/                        # CleanupCategory, DiskUsageInfo, LargeFile, ...
├── Services/                      # Actor-based: CleanupService, FileSystemScanner,
│                                  # ShellCommandRunner, AppUninstallerService,
│                                  # LargeFileFinder, DuplicateFileFinder, ...
├── ViewModels/                    # @MainActor ObservableObject view models
├── Views/                         # NavigationSplitView + sidebar + Smart Clean hero
│                                  # + per-tool views + onboarding + settings
├── Utilities/                     # ByteFormatter, Constants, DesignSystem (theme tokens)
Tests/MacCleanerTests/             # XCTest: ByteFormatter, ShellCommandRunner.shellQuote,
                                   # DiskUsageInfo, shell-injection round-trip tests
```

**Design principles:**
- **Three-layer split**: Models / Services / ViewModels — Views never touch the file system.
- **Actor-isolated services** for thread-safe concurrent scanning.
- **Two-step destructive flow**: every destructive operation requires a confirmation sheet.
- **Path quoting**: every shell command interpolates paths via `ShellCommandRunner.shellQuote(_:)` (single-quoted, embedded quotes escaped). Round-trip tested against an injection-payload battery.
- **Trash, not unlink**: Large Files and Duplicates use `FileManager.trashItem` so deletion is recoverable.

## Roadmap

- Code signing + notarization in the release pipeline (Developer ID required)
- Homebrew cask: `brew install --cask maccleaner`
- Localization (zh-Hans, ja, de, fr, es, pt-BR, ru)
- Plugin API for community-contributed cleanup categories
- Scheduled auto-clean via `SMAppService`
- Universal binary (currently arm64; Intel via `--arch x86_64`)

See the [open issues](https://github.com/codewprincee/MacCleaner/issues) labelled `roadmap`.

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, code style (SwiftLint + SwiftFormat), commit conventions, and the "how to add a new cleanup category" mini-tutorial.

## License

[MIT](LICENSE) — see also [SECURITY.md](SECURITY.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Acknowledgements

- [Sparkle](https://sparkle-project.org/) — auto-update framework
- [SF Symbols](https://developer.apple.com/sf-symbols/) — UI iconography
- Everyone who tried CleanMyMac and thought "this should be free and open source"
