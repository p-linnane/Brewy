@testable import Brewy
import Foundation
import Testing

@Suite("CommandResult")
struct CommandResultTests {

    @Test("CommandResult is Sendable and stores output + success")
    func basicFields() {
        let result = CommandResult(output: "hi", success: true)
        #expect(result.output == "hi")
        #expect(result.success)
    }
}

@Suite("MockCommandRunner Behavior")
struct MockCommandRunnerBehaviorTests {

    @Test("Returns configured result for matching arguments")
    func returnsConfiguredResult() async {
        let mock = MockCommandRunner()
        mock.setResult(for: ["install", "wget"], output: "done", success: true)
        let result = await mock.run(["install", "wget"], brewPath: "/bin/true")
        #expect(result.success)
        #expect(result.output == "done")
    }

    @Test("Returns failure fallback for unconfigured arguments")
    func unconfiguredFallsBack() async {
        let mock = MockCommandRunner()
        let result = await mock.run(["never-set"], brewPath: "/bin/true")
        #expect(!result.success)
        #expect(result.output.isEmpty)
    }

    @Test("Records executed commands in order")
    func recordsExecutedCommands() async {
        let mock = MockCommandRunner()
        mock.setResult(for: ["a"], output: "", success: true)
        mock.setResult(for: ["b"], output: "", success: true)
        _ = await mock.run(["a"], brewPath: "/bin/true")
        _ = await mock.run(["b"], brewPath: "/bin/true")
        #expect(mock.executedCommands == [["a"], ["b"]])
    }
}

/// Real-subprocess coverage for `CommandRunner.runExecutable`. Skipped on
/// GitHub Actions runners (detected via `/Users/runner`): `Pipe` +
/// `readDataToEndOfFile()` stopped observing EOF after the child exits
/// there, on both macos-15 and macos-26 images, some time between
/// April 17 and April 20. The hang reproduces even for `/bin/echo`, even
/// with the suite serialized, even after explicitly closing the parent's
/// copy of the pipe write-ends — so it's not parallelism or our FD
/// bookkeeping. Suspect a Foundation.Process/Pipe regression on the
/// runner image. The same code passes locally on macOS 15 under TSAN in
/// ~1s and it ran fine on macos-26 CI as recently as April 17, so no
/// product-visible bug. Runs locally via `just test`.
@Suite(
    "CommandRunner Process Execution",
    .disabled(
        if: FileManager.default.fileExists(atPath: "/Users/runner"),
        "Subprocess pipe reads hang on GitHub Actions runners — run locally instead"
    )
)
struct CommandRunnerProcessTests {

    @Test("runExecutable captures stdout from echo")
    func echoStdout() async {
        let result = await CommandRunner.runExecutable("/bin/echo", arguments: ["hello", "world"])
        #expect(result.success)
        #expect(result.output.contains("hello world"))
    }

    @Test("runExecutable reports failure for nonzero exit")
    func nonzeroExit() async {
        let result = await CommandRunner.runExecutable("/usr/bin/false", arguments: [])
        #expect(!result.success)
    }

    @Test("runExecutable captures stderr when stdout is empty")
    func stderrFallback() async {
        let result = await CommandRunner.runExecutable(
            "/bin/sh",
            arguments: ["-c", "echo error-message >&2; exit 2"]
        )
        #expect(!result.success)
        #expect(result.output.contains("error-message"))
    }

    @Test("runExecutable prefers stdout over stderr when both produced")
    func stdoutWinsOverStderr() async {
        let result = await CommandRunner.runExecutable(
            "/bin/sh",
            arguments: ["-c", "echo stdout-line; echo stderr-line >&2"]
        )
        #expect(result.success)
        #expect(result.output.contains("stdout-line"))
    }

    @Test("runExecutable times out a long-running process")
    func timeoutKillsProcess() async {
        let start = ContinuousClock.now
        let result = await CommandRunner.runExecutable(
            "/bin/sh",
            arguments: ["-c", "sleep 30"],
            timeout: .seconds(1)
        )
        let elapsed = ContinuousClock.now - start
        #expect(!result.success)
        #expect(elapsed < .seconds(15))
    }

    @Test("runExecutable handles missing executable gracefully")
    func missingExecutable() async {
        let result = await CommandRunner.runExecutable(
            "/nonexistent/path/to/binary",
            arguments: []
        )
        #expect(!result.success)
        #expect(!result.output.isEmpty)
    }

    @Test("runExecutable drains large stdout without deadlock")
    func largeOutputDrains() async {
        let result = await CommandRunner.runExecutable(
            "/bin/sh",
            arguments: ["-c", "yes output | head -n 10000"]
        )
        #expect(result.success)
        let lineCount = result.output.split(separator: "\n").count
        #expect(lineCount >= 10_000)
    }
}
