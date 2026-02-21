import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "CommandRunner")

// MARK: - Command Result

struct CommandResult: Sendable {
    let output: String
    let success: Bool
}

// MARK: - Locked Data Accumulator

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
        let result = chunks.reduce(Data(), +)
        lock.unlock()
        return result
    }
}

// MARK: - Command Runner

/// Executes Homebrew CLI commands with timeout, cancellation, and logging.
enum CommandRunner {

    /// Default timeout for brew commands (5 minutes).
    static let defaultTimeout: Duration = .seconds(300)

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
        let commandDescription = "brew \(arguments.joined(separator: " "))"
        logger.info("Running: \(commandDescription)")
        let startTime = ContinuousClock.now

        let result = await Task.detached(priority: .medium) {
            executeProcess(
                arguments: arguments,
                brewPath: brewPath,
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

    // MARK: - Private

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
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            // Schedule a timeout to terminate the process if it runs too long
            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    logger.warning("Terminating timed-out process: \(commandDescription)")
                    process.terminate()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + .seconds(Int(timeout.components.seconds)),
                execute: timeoutWork
            )

            // Read stderr asynchronously to avoid pipe deadlock.
            let stderrAccumulator = LockedData()
            let stderrSemaphore = DispatchSemaphore(value: 0)
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    stderrSemaphore.signal()
                } else {
                    stderrAccumulator.append(chunk)
                }
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            stderrSemaphore.wait()
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            process.waitUntilExit()
            timeoutWork.cancel()

            let stderrData = stderrAccumulator.combined()

            let output = String(data: stdoutData, encoding: .utf8) ?? ""
            let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""
            let combinedOutput = output.isEmpty ? errorOutput : output

            // Detect if the process was killed by the timeout (SIGTERM = 15)
            if process.terminationReason == .uncaughtSignal {
                return CommandResult(output: "Command timed out after \(timeout)", success: false)
            }

            return CommandResult(output: combinedOutput, success: process.terminationStatus == 0)
        } catch {
            logger.error("Failed to launch process: \(error.localizedDescription)")
            return CommandResult(
                output: "Failed to run brew: \(error.localizedDescription)",
                success: false
            )
        }
    }
}
