import Foundation

actor DockerService {
    private let shell: ShellCommandRunner

    init(shell: ShellCommandRunner = ShellCommandRunner()) {
        self.shell = shell
    }

    func isDockerAvailable() async -> Bool {
        await shell.isToolAvailable(Constants.dockerCheckCommand)
    }

    func estimateDiskUsage() async -> Int64 {
        guard let result = try? await shell.run(
            "docker system df --format '{{.Size}}' 2>/dev/null",
            timeout: 15
        ), result.success else {
            return 0
        }
        return parseDockerSizes(result.output)
    }

    func prune() async throws -> Int64 {
        let sizeBefore = await estimateDiskUsage()
        // docker prune can take a while on large systems
        let result = try await shell.run(Constants.dockerPruneCommand, timeout: 600)

        if !result.success {
            throw CleanupError.commandFailed(result.output)
        }

        let sizeAfter = await estimateDiskUsage()
        return max(sizeBefore - sizeAfter, 0)
    }

    private func parseDockerSizes(_ output: String) -> Int64 {
        let lines = output.components(separatedBy: "\n")
        var total: Int64 = 0
        for line in lines {
            total += parseSizeString(line.trimmingCharacters(in: .whitespaces))
        }
        return total
    }

    private func parseSizeString(_ str: String) -> Int64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }

        let units: [(String, Double)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("kB", 1024),
            ("B", 1),
        ]

        for (unit, multiplier) in units {
            if trimmed.hasSuffix(unit) {
                let numStr = trimmed.dropLast(unit.count).trimmingCharacters(in: .whitespaces)
                if let value = Double(numStr) {
                    return Int64(value * multiplier)
                }
            }
        }
        return 0
    }
}

enum CleanupError: LocalizedError {
    case commandFailed(String)
    case notAvailable(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .notAvailable(let tool): return "\(tool) is not available"
        }
    }
}
