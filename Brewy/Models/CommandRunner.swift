import Darwin
import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "CommandRunner")

// MARK: - Command Result

struct CommandResult: Sendable {
    let output: String
    let success: Bool
    let didTimeOut: Bool

    init(output: String, success: Bool, didTimeOut: Bool = false) {
        self.output = output
        self.success = success
        self.didTimeOut = didTimeOut
    }
}

// MARK: - Thread-safe Value Containers

/// Thread-safe accumulator for data chunks.
private final class LockedData: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var chunks: [Data] = []

    func append(_ data: Data) {
        lock.lock()
        chunks.append(data)
        lock.unlock()
    }

    func combined() -> Data {
        lock.lock()
        var result = Data()
        result.reserveCapacity(chunks.reduce(0) { $0 + $1.count })
        for chunk in chunks { result.append(chunk) }
        lock.unlock()
        return result
    }
}

private final class LockedFlag: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var value = false

    func set() { lock.lock(); value = true; lock.unlock() }

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

// MARK: - Command Running Protocol

protocol CommandRunning: Sendable {
    func run(_ arguments: [String], brewPath: String, timeout: Duration) async -> CommandResult
    func runExecutable(_ executablePath: String, arguments: [String], timeout: Duration) async -> CommandResult
}

extension CommandRunning {
    func run(_ arguments: [String], brewPath: String) async -> CommandResult {
        await run(arguments, brewPath: brewPath, timeout: CommandRunner.defaultTimeout)
    }

    func runExecutable(_ executablePath: String, arguments: [String]) async -> CommandResult {
        await runExecutable(executablePath, arguments: arguments, timeout: CommandRunner.defaultTimeout)
    }
}

// MARK: - Default Command Runner

struct DefaultCommandRunner: CommandRunning {
    func run(_ arguments: [String], brewPath: String, timeout: Duration) async -> CommandResult {
        await CommandRunner.run(arguments, brewPath: brewPath, timeout: timeout)
    }

    func runExecutable(_ executablePath: String, arguments: [String], timeout: Duration) async -> CommandResult {
        await CommandRunner.runExecutable(executablePath, arguments: arguments, timeout: timeout)
    }
}

// MARK: - Command Runner

enum CommandRunner {

    static let defaultTimeout: Duration = .seconds(300)

    /// Grace period between SIGTERM and SIGKILL when a process exceeds its timeout.
    private static let killGracePeriod: Duration = .seconds(3)

    static func resolvedBrewPath(preferred: String) -> String {
        let fallback = "/usr/local/bin/brew"
        if FileManager.default.isExecutableFile(atPath: preferred) { return preferred }
        if FileManager.default.isExecutableFile(atPath: fallback) { return fallback }
        return preferred
    }

    static func run(
        _ arguments: [String],
        brewPath: String,
        timeout: Duration = defaultTimeout
    ) async -> CommandResult {
        await runExecutable(brewPath, arguments: arguments, timeout: timeout)
    }

    static func runExecutable(
        _ executablePath: String,
        arguments: [String],
        timeout: Duration = defaultTimeout
    ) async -> CommandResult {
        let execName = URL(fileURLWithPath: executablePath).lastPathComponent
        let commandDescription = "\(execName) \(arguments.joined(separator: " "))"
        logger.info("Running: \(commandDescription)")
        let startTime = ContinuousClock.now

        let result = await Task.detached(priority: .medium) {
            executeProcess(
                arguments: arguments,
                brewPath: executablePath,
                timeout: timeout,
                commandDescription: commandDescription
            )
        }.value

        let elapsed = ContinuousClock.now - startTime
        if result.success {
            logger.info("\(commandDescription) completed in \(elapsed)")
        } else {
            logger.warning("\(commandDescription) failed after \(elapsed): \(result.output.prefix(200))")
        }

        return result
    }

    static func resolvedMasPath() -> String {
        let paths = ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return paths[0]
    }

    // MARK: - Private

    private static func buildEnvironment(brewPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewBin = URL(fileURLWithPath: brewPath).deletingLastPathComponent().path
        let brewPrefix = URL(fileURLWithPath: brewBin).deletingLastPathComponent().path
        let brewSbin = brewPrefix + "/sbin"

        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var pathComponents = currentPath.components(separatedBy: ":")

        for dir in [brewSbin, brewBin] where !pathComponents.contains(dir) {
            pathComponents.insert(dir, at: 0)
        }

        env["PATH"] = pathComponents.joined(separator: ":")
        return env
    }

    /// Convert a `Duration` into a `DispatchTimeInterval` that preserves sub-second precision.
    private static func dispatchInterval(from duration: Duration) -> DispatchTimeInterval {
        let components = duration.components
        let totalNanos = components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
        if totalNanos > Int64(Int.max) { return .seconds(Int.max) }
        return .nanoseconds(Int(totalNanos))
    }

    private static func executeProcess(
        arguments: [String],
        brewPath: String,
        timeout: Duration,
        commandDescription: String
    ) -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments
        process.environment = buildEnvironment(brewPath: brewPath)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch process: \(error.localizedDescription)")
            return CommandResult(
                output: "Failed to run \(commandDescription): \(error.localizedDescription)",
                success: false
            )
        }

        let (stdoutData, stderrData) = drainPipesInParallel(stdout: stdoutPipe, stderr: stderrPipe)
        let timedOut = scheduleTimeout(for: process, after: timeout, commandDescription: commandDescription)

        process.waitUntilExit()
        let out = stdoutData.wait()
        let err = stderrData.wait()

        if timedOut.isSet {
            return CommandResult(
                output: "Command timed out after \(timeout).",
                success: false,
                didTimeOut: true
            )
        }
        let stdout = String(data: out, encoding: .utf8) ?? ""
        let stderr = String(data: err, encoding: .utf8) ?? ""
        return CommandResult(
            output: stdout.isEmpty ? stderr : stdout,
            success: process.terminationStatus == 0
        )
    }

    private static func drainPipesInParallel(stdout: Pipe, stderr: Pipe) -> (stdout: PipeReader, stderr: PipeReader) {
        let stdoutReader = PipeReader(pipe: stdout)
        let stderrReader = PipeReader(pipe: stderr)
        stdoutReader.start()
        stderrReader.start()
        return (stdoutReader, stderrReader)
    }

    private static func scheduleTimeout(
        for process: Process,
        after timeout: Duration,
        commandDescription: String
    ) -> LockedFlag {
        let timedOut = LockedFlag()
        let timeoutWork = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            logger.warning("Timeout exceeded, sending SIGTERM: \(commandDescription)")
            timedOut.set()
            process.terminate()
            let pid = process.processIdentifier
            let graceDispatch = dispatchInterval(from: killGracePeriod)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + graceDispatch) { [weak process] in
                guard let process, process.isRunning else { return }
                logger.warning("SIGTERM ignored, sending SIGKILL: \(commandDescription)")
                kill(pid, SIGKILL)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + dispatchInterval(from: timeout),
            execute: timeoutWork
        )
        return timedOut
    }
}

// MARK: - Pipe Reader

/// Drains a `Pipe` to EOF on a background queue so the subprocess cannot deadlock on a full buffer.
private final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let accumulator = LockedData()
    private let semaphore = DispatchSemaphore(value: 0)

    init(pipe: Pipe) { self.pipe = pipe }

    func start() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            accumulator.append(data)
            semaphore.signal()
        }
    }

    func wait() -> Data {
        semaphore.wait()
        return accumulator.combined()
    }
}
