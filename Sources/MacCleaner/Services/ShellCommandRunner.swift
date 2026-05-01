import Foundation

actor ShellCommandRunner {
    struct CommandResult {
        let output: String
        let exitCode: Int32
        var success: Bool { exitCode == 0 }
    }

    enum ShellError: LocalizedError {
        case timedOut(seconds: Int)
        case launchFailed(String)
        case authorizationDenied

        var errorDescription: String? {
            switch self {
            case .timedOut(let s): return "Command timed out after \(s)s"
            case .launchFailed(let msg): return "Failed to launch process: \(msg)"
            case .authorizationDenied: return "Administrator authorization denied or cancelled"
            }
        }
    }

    private let defaultTimeoutSeconds: Int = 120

    /// Run a shell command via login zsh. The full `command` string is passed as a single
    /// argument to `zsh -l -c`, so do NOT interpolate untrusted input — use `shellQuote`
    /// to wrap any path or argument that may contain spaces or metacharacters.
    func run(_ command: String, timeout: Int? = nil) async throws -> CommandResult {
        try await runProcess(
            executable: Constants.shellPath,
            arguments: Constants.shellArgs + [command],
            timeoutSeconds: timeout ?? defaultTimeoutSeconds
        )
    }

    /// Run a command with administrator privileges via `osascript do shell script`.
    /// This double-evaluates the string (AppleScript -> shell), so the command is
    /// strictly escaped for both layers.
    func runWithPrivileges(_ command: String, timeout: Int? = nil) async throws -> CommandResult {
        let appleScript = "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges"
        do {
            return try await runProcess(
                executable: "/usr/bin/osascript",
                arguments: ["-e", appleScript],
                timeoutSeconds: timeout ?? defaultTimeoutSeconds
            )
        } catch ShellError.timedOut(let s) {
            throw ShellError.timedOut(seconds: s)
        }
    }

    func isToolAvailable(_ checkCommand: String) async -> Bool {
        guard let result = try? await run(checkCommand, timeout: 10) else {
            return false
        }
        return result.success
    }

    /// Quote a single argument for safe interpolation into a shell command string.
    /// Wraps in single quotes and escapes embedded single quotes.
    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Internal

    private func runProcess(
        executable: String,
        arguments: [String],
        timeoutSeconds: Int
    ) async throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        // Stream pipe data into a buffer to avoid the OS pipe buffer (~64KB) deadlock.
        let collector = OutputCollector()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let chunk = fh.availableData
            if chunk.isEmpty {
                fh.readabilityHandler = nil
            } else {
                collector.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            throw ShellError.launchFailed(error.localizedDescription)
        }

        // Race process termination against a timeout.
        let timeoutTask = Task<Void, Error> { [process] in
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            if process.isRunning { process.terminate() }
            // Give it a moment to die, then force-kill if still alive.
            try? await Task.sleep(nanoseconds: 500_000_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            throw ShellError.timedOut(seconds: timeoutSeconds)
        }

        let waitTask = Task<Int32, Never> {
            await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
                process.terminationHandler = { p in
                    cont.resume(returning: p.terminationStatus)
                }
            }
        }

        do {
            let exitCode = try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask { await waitTask.value }
                group.addTask {
                    try await timeoutTask.value
                    return -1
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            timeoutTask.cancel()

            // Drain any remaining buffered data.
            handle.readabilityHandler = nil
            let leftover = (try? handle.readToEnd()) ?? Data()
            if !leftover.isEmpty { collector.append(leftover) }

            let output = collector.string().trimmingCharacters(in: .whitespacesAndNewlines)
            let mappedExit = mapAuthorizationDenied(executable: executable, exitCode: exitCode, output: output)
            if case .failure(let err) = mappedExit { throw err }
            return CommandResult(output: output, exitCode: exitCode)
        } catch is CancellationError {
            if process.isRunning { process.terminate() }
            throw ShellError.timedOut(seconds: timeoutSeconds)
        } catch let err as ShellError {
            if process.isRunning { process.terminate() }
            throw err
        }
    }

    private func mapAuthorizationDenied(
        executable: String,
        exitCode: Int32,
        output: String
    ) -> Result<Void, ShellError> {
        // osascript exits with 1 on user cancel, with errAEEventNotPermitted (-1743) etc.
        // The classic cancel marker is "User canceled." in stderr.
        if executable == "/usr/bin/osascript" && exitCode != 0 {
            let lower = output.lowercased()
            if lower.contains("user canceled") || lower.contains("user cancelled") || lower.contains("(-128)") {
                return .failure(.authorizationDenied)
            }
        }
        return .success(())
    }

    private nonisolated func escapeForAppleScript(_ command: String) -> String {
        // AppleScript double-quoted strings interpret \, ", and convert nothing else.
        // The shell layer (do shell script) uses /bin/sh and would re-evaluate metacharacters
        // INSIDE the AppleScript string only after AppleScript decoding, so escaping \ and "
        // here is sufficient for the AppleScript layer. The caller is responsible for
        // ensuring the resulting shell command is safe (use shellQuote for paths).
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// Reference type so the readabilityHandler closure can append safely.
private final class OutputCollector: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
    }

    func string() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}
