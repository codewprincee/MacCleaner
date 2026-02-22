# MacCleaner

A native macOS app to scan and clean system caches, build artifacts, and Docker data. Built with SwiftUI.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **18 cleanup categories** across 6 groups
- **Concurrent scanning** - all categories scanned in parallel
- **Admin privilege support** - native macOS password prompt for system-level cleanup
- **Smart protection** - automatically skips system-owned files that can't be deleted
- **Graceful degradation** - unavailable tools shown as disabled
- **Disk usage bar** - visual overview of your storage

### Cleanup Categories

| Group | Categories |
|-------|-----------|
| **File System** | User Caches, System Logs, Temp Files, Trash |
| **Xcode** | Derived Data, iOS Device Support, iOS Simulators, Archives |
| **Browsers** | Safari Cache, Chrome Cache |
| **Package Managers** | Homebrew, npm, pip, Yarn, CocoaPods |
| **System** (admin) | System Caches, DNS Cache |
| **Containers** | Docker Data |

## Install

### Option 1: Install Script (recommended)

```bash
git clone https://github.com/codewprincee/MacCleaner.git
cd MacCleaner
./install.sh
```

This builds a release binary and installs `MacCleaner.app` to `/Applications`.

### Option 2: Build & Run

```bash
git clone https://github.com/codewprincee/MacCleaner.git
cd MacCleaner
swift build -c release
swift run MacCleaner
```

### Option 3: Open in Xcode

```bash
open Package.swift
```

Then press Cmd+R to build and run.

## Uninstall

```bash
cd MacCleaner
./uninstall.sh
```

Or just delete `/Applications/MacCleaner.app`.

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+
- Xcode Command Line Tools (`xcode-select --install`)

## Architecture

```
Sources/MacCleaner/
├── MacCleanerApp.swift          # Entry point
├── Models/
│   ├── CleanupCategory.swift    # 18 cleanup types + data model
│   ├── CleanupResult.swift      # Result/error tracking
│   └── DiskUsageInfo.swift      # Disk space queries
├── Services/
│   ├── ShellCommandRunner.swift # Async shell + admin privilege escalation
│   ├── FileSystemScanner.swift  # Directory scanning + safe deletion
│   ├── DockerService.swift      # Docker status + prune
│   └── CleanupService.swift     # Main orchestrator
├── ViewModels/
│   └── CleanupViewModel.swift   # UI state management
├── Views/
│   ├── ContentView.swift        # Main layout
│   ├── CategoryListView.swift   # Grouped category sections
│   ├── CategoryRowView.swift    # Individual category row
│   ├── DiskUsageBarView.swift   # Storage visualization
│   ├── CleanupProgressView.swift
│   ├── CleanupSummaryView.swift # Results + error details
│   └── ToolbarView.swift        # Actions bar
└── Utilities/
    ├── ByteFormatter.swift      # Human-readable sizes
    └── Constants.swift          # Paths + commands
```

**Key design decisions:**
- **Actor-based services** for thread-safe concurrent scanning
- **Login shell** (`/bin/zsh -l -c`) ensures PATH includes Homebrew, npm, etc.
- **`osascript`** for admin password prompts (native macOS dialog)
- **Protected file skipping** - won't attempt to delete `com.apple.*` system caches

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

[MIT](LICENSE)
