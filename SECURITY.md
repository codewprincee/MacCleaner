# Security Policy

## Reporting a Vulnerability

If you find a security vulnerability in MacCleaner, please **do not open a public issue**. Email the maintainer directly:

- **Email:** princeks@blendapp.ae
- **Subject prefix:** `[MacCleaner Security]`

You should expect an initial response within 72 hours. We will keep you updated as we investigate, develop a fix, and prepare a coordinated release.

## Supported Versions

Only the latest released version of MacCleaner receives security updates. Please ensure you are running the most recent release before reporting an issue.

| Version  | Supported          |
| -------- | ------------------ |
| 1.x.x    | :white_check_mark: |
| < 1.0    | :x:                |

## Threat Model

MacCleaner runs as an unsandboxed user-level macOS application. A subset of cleanup operations escalate to administrator privileges via `osascript do shell script with administrator privileges`. We take the integrity of that escalation surface seriously.

### What we protect against

- **Shell injection in privileged operations.** Every path passed to a privileged shell command is single-quoted via `ShellCommandRunner.shellQuote(_:)`, which escapes embedded single quotes (`'\''`). The privileged `find ... -mindepth 1 -delete` form is used instead of glob-expanded `rm -rf`, so dangerous metacharacters in a path cannot break out of the intended deletion target. Round-trip tests in `Tests/MacCleanerTests/ShellCommandRunnerQuoteTests.swift` exercise this contract against a battery of injection payloads.
- **Pipe deadlocks.** Process I/O is read via a streaming `readabilityHandler` so commands producing large output (`brew cleanup`, `docker system prune`) cannot fill the OS pipe buffer and hang the app.
- **Command timeouts.** Every shell invocation is bounded by a timeout (default 120s, 600s for Docker, 10s for availability checks). Hung processes are sent SIGTERM, then SIGKILL.
- **Confirmation gating.** All multi-category cleanups route through `requestCleanSelected()` → `CleanupConfirmationView` → `confirmAndCleanSelected()`. The user must explicitly approve before any destructive operation runs.
- **Running-process detection.** `RunningProcessDetector` consults `NSWorkspace.runningApplications` and surfaces a warning when the user attempts to clean caches owned by a currently-running app (Safari, Chrome, Xcode, etc.).
- **Path traversal in App Uninstaller.** Resolved leftover paths are checked to start with `NSHomeDirectory()` or `/Library` before deletion. Symbolic links are not followed during enumeration.
- **Self-destruction guard.** The App Uninstaller refuses to uninstall MacCleaner itself.

### What we don't claim

- **Sandbox protection.** MacCleaner is not sandboxed; that is incompatible with cleaning system caches across the user's Library tree. Users should obtain releases only from the official GitHub Releases page or a trusted package manager.
- **Code signing on every build.** Local `./install.sh` produces an unsigned binary that triggers Gatekeeper. Signed and notarized builds are produced only by the GitHub Actions release workflow with secrets configured.

## Disclosure

We follow coordinated disclosure. Once a fix is shipped, we will credit the reporter (with permission) in the release notes and CHANGELOG.
