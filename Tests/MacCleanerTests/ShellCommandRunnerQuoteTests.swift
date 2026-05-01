import XCTest
@testable import MacCleaner

/// Verifies `ShellCommandRunner.shellQuote` produces strings that, when fed back
/// through `/bin/sh -c "echo <quoted>"`, recover the original input byte-for-byte.
/// This is the contract that prevents shell injection in privileged operations.
final class ShellCommandRunnerQuoteTests: XCTestCase {
    func testSimplePath() {
        XCTAssertEqual(
            ShellCommandRunner.shellQuote("/Users/foo/Library"),
            "'/Users/foo/Library'"
        )
    }

    func testPathWithSpaces() throws {
        let input = "/Users/john doe/My Documents"
        let quoted = ShellCommandRunner.shellQuote(input)
        try assertRoundTrips(input: input, quoted: quoted)
    }

    func testPathWithSingleQuote() throws {
        let input = "/Users/o'malley/Library"
        let quoted = ShellCommandRunner.shellQuote(input)
        XCTAssertEqual(quoted, #"'/Users/o'\''malley/Library'"#)
        try assertRoundTrips(input: input, quoted: quoted)
    }

    func testInjectionAttempt() throws {
        // Classic shell-injection payloads — must all round-trip as literal data,
        // never as executable shell.
        let payloads = [
            "; rm -rf /",
            "$(rm -rf ~)",
            "`whoami`",
            "&& echo PWNED",
            "|| true",
            "\"; cat /etc/passwd; echo \"",
            "\\; echo escaped",
        ]
        for payload in payloads {
            let quoted = ShellCommandRunner.shellQuote(payload)
            try assertRoundTrips(input: payload, quoted: quoted)
        }
    }

    func testEmptyString() throws {
        let quoted = ShellCommandRunner.shellQuote("")
        XCTAssertEqual(quoted, "''")
        try assertRoundTrips(input: "", quoted: quoted)
    }

    // MARK: - Helpers

    /// Runs `echo <quoted>` through /bin/sh and compares the output to the original input.
    /// Any quoting bug shows up as either an injection (extra output) or a corrupted result.
    private func assertRoundTrips(input: String, quoted: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' \(quoted)"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(output, input, "shellQuote round-trip mismatch for \(input.debugDescription)", file: file, line: line)
    }
}
