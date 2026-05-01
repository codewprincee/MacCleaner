# Contributing to MacCleaner

First off — thank you for taking the time to contribute! MacCleaner is a
community-driven, MIT-licensed macOS app, and every PR, bug report, and
discussion makes it better.

This document covers how to set up the dev environment, the conventions we
use, and the process for getting changes merged.

---

## Code of Conduct

This project and everyone participating in it is governed by the
[Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating
you are expected to uphold this code. Please report unacceptable behavior to
the maintainer email listed in the Code of Conduct.

---

## Development environment

### Requirements

- **macOS 14 (Sonoma) or later** — required to run the app and the tests.
- **Xcode 15.0 or later** — install from the Mac App Store, then run
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- **Swift 5.9+** (ships with Xcode 15).
- **Command Line Tools** — `xcode-select --install` if you do not have
  the full Xcode app.
- **SwiftLint** — `brew install swiftlint`.
- **SwiftFormat** — `brew install swiftformat`.

### Cloning and building

```bash
git clone https://github.com/codewprincee/MacCleaner.git
cd MacCleaner

# Build (treat warnings as errors, just like CI does)
swift build -Xswiftc -warnings-as-errors

# Run the app from the command line
swift run MacCleaner

# Or open the package in Xcode and press Cmd+R
open Package.swift
```

### Running the test suite

```bash
swift test
```

To get coverage data:

```bash
swift test --enable-code-coverage
```

CI runs the full matrix on `macos-14` and `macos-15`. Please make sure your
PR is green before requesting review.

---

## Code style

We enforce style automatically:

- **SwiftLint** — strict mode in CI. Run `swiftlint` locally before pushing.
- **SwiftFormat** — lint mode in CI. Run `swiftformat .` to auto-fix.

Configuration lives in `.swiftlint.yml` and `.swiftformat`. Please don't
disable rules in individual files unless you have a strong reason.

Beyond the linters:

- **Async/await everywhere.** No callbacks. No `.then()` chains.
- **Early returns** for guard clauses. Avoid deep nesting.
- **Descriptive variable and function names.** No one-letter names except
  `i` / `j` in tight loops.
- **Comments explain "why", never "what".** The code already says what.
- **Single responsibility.** One function does one thing.

---

## Branch naming

Use a short, kebab-cased description prefixed with the change type:

| Prefix | When to use |
|--------|-------------|
| `feat/` | New feature |
| `fix/` | Bug fix |
| `docs/` | Documentation only |
| `refactor/` | Internal cleanup, no behavior change |
| `test/` | Adding or fixing tests |
| `chore/` | Tooling, CI, dependency bumps |

Examples: `feat/duplicate-finder-progress`, `fix/docker-prune-timeout`,
`docs/contributing-tutorial`.

---

## Commit messages

We follow [**Conventional Commits**](https://www.conventionalcommits.org).
The header line should be `<type>(<scope>): <subject>`:

```
feat(menubar): add quick-clean shortcut for last-used preset
fix(shell): kill child process on Task cancellation
docs(readme): document Sparkle feed-URL setup
chore(ci): bump setup-xcode to v1.6.0
```

Allowed types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`,
`perf`, `build`, `ci`, `style`.

> [!IMPORTANT]
> **Never add `Co-Authored-By: Claude` (or any AI attribution) to commit
> messages.** This is a project rule. Commits that include AI co-author
> trailers will be rejected and you will be asked to amend them.

---

## Pull request process

1. **Fork** the repo and create a feature branch off `main`.
2. **Write tests** for any logic change. UI-only changes need at least one
   manual repro screenshot or screen recording.
3. **Run locally:**
   ```bash
   swift build -Xswiftc -warnings-as-errors
   swift test
   swiftlint --strict
   swiftformat --lint .
   ```
4. **Open a PR** filling out the [PR template](.github/PULL_REQUEST_TEMPLATE.md).
5. **Wait for CI** to go green on both `macos-14` and `macos-15`.
6. A maintainer will review. We try to respond within a few days. Address
   feedback by pushing more commits to the same branch — we squash on
   merge, so don't worry about a tidy commit history.

---

## Architecture overview

MacCleaner is structured into clean layers under `Sources/MacCleaner/`:

```
Sources/MacCleaner/
├── MacCleanerApp.swift   # Entry point, scene wiring, menu commands
├── MenuBar/              # Menu bar mode (NSStatusItem-backed)
├── Models/               # Plain value types: CleanupCategory, CleanupResult, ...
├── Services/             # Actor-based business logic. Owns shell, file IO, Docker.
├── ViewModels/           # @MainActor state holders bridging Services to Views.
├── Views/                # SwiftUI views. Free of business logic.
└── Utilities/            # Pure helpers: ByteFormatter, Constants, DesignSystem.
```

Key design choices:

- **Actor-based services** keep concurrent scanning thread-safe by default.
- **Login-shell zsh** (`/bin/zsh -l -c`) is used for shell commands so that
  Homebrew, npm, pyenv, etc. resolve via the user's `PATH`.
- **`osascript do shell script ... with administrator privileges`** drives
  the native macOS authentication dialog for system-level cleanups.
- **Two-step destructive confirmation** — every delete-class action requires
  a second deliberate confirmation. There is no "remember my choice".
- **Protected-path skipping** — we never touch `com.apple.*` system caches
  or anything outside the allowlist defined in `Constants.swift`.

---

## How to add a new cleanup category

This is the most common contribution. The flow is:

1. **Add an enum case** in `Sources/MacCleaner/Models/CleanupCategory.swift`
   with the display name, icon, group, and admin-required flag.
2. **Add a switch arm** in `Sources/MacCleaner/Services/CleanupService.swift`
   that returns the scan function (size estimate) and clean function (actual
   delete) for your category. If your category just needs to remove paths,
   reuse `FileSystemScanner`. If it shells out (e.g. `npm cache clean
   --force`), reuse `ShellCommandRunner` and **always quote paths via
   `ShellCommandRunner.shellQuote`**.
3. **Add the category to the right group** in
   `Sources/MacCleaner/Utilities/DesignSystem.swift` under `CategoryGroup`
   so it shows up in the right sidebar section with the right tint.
4. **Add a test** in `Tests/MacCleanerTests` if your category has any
   non-trivial parsing or path resolution logic.

That's it. The UI, scan/clean orchestration, progress reporting, and
two-step confirmation flow are all driven by these three files.

---

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml). The
more precisely you can describe the macOS version, app version, repro
steps, and (ideally) a Console.app log filtered to "MacCleaner", the
faster we can fix it.

For **security vulnerabilities**, please follow [SECURITY.md](SECURITY.md)
instead of filing a public issue.

---

## License

By contributing to MacCleaner, you agree that your contributions will be
licensed under its [MIT License](LICENSE).
