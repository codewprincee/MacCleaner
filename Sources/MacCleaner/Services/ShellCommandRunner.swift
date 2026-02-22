import Foundation

actor ShellCommandRunner {
    struct CommandResult {
        let output: String
        let exitCode: Int32
        var success: Bool { exitCode == 0 }
    }

    func run(_ command: String) async throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: Constants.shellPath)
        process.arguments = Constants.shellArgs + [command]
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: CommandResult(
                    output: output,
                    exitCode: process.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func runWithPrivileges(_ command: String) async throws -> CommandResult {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = "do shell script \"\(escapedCommand)\" with administrator privileges"

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: CommandResult(
                    output: output,
                    exitCode: process.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func isToolAvailable(_ checkCommand: String) async -> Bool {
        guard let result = try? await run(checkCommand) else {
            return false
        }
        return result.success
    }
}
