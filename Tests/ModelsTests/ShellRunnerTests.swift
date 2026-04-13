import Foundation
import Testing

@testable import Models

@Test func shellRunnerTimesOutLongProcess() async throws {
    // `sleep 60` will never finish in 1 second — should throw .timeout
    do {
        _ = try await ShellRunner.run(
            executable: "/bin/sleep",
            args: ["60"],
            timeout: .seconds(1)
        )
        Issue.record("Expected ShellError.timeout but run() succeeded")
    } catch let error as ShellError {
        guard case .timeout(let executable, let args) = error else {
            Issue.record("Expected .timeout but got \(error)")
            return
        }
        #expect(executable == "/bin/sleep")
        #expect(args == ["60"])
    }
}

@Test func shellRunnerSucceedsWithinTimeout() async throws {
    let output = try await ShellRunner.run(
        executable: "/bin/echo",
        args: ["hello"],
        timeout: .seconds(10)
    )
    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
}

@Test func shellRunnerReportsNonZeroExitAsCommandFailed() async throws {
    // /usr/bin/false always exits with status 1
    do {
        _ = try await ShellRunner.run(
            executable: "/usr/bin/false",
            args: [],
            timeout: .seconds(5)
        )
        Issue.record("Expected ShellError.commandFailed but run() succeeded")
    } catch let error as ShellError {
        guard case .commandFailed(_, _, let exitCode, _) = error else {
            Issue.record("Expected .commandFailed but got \(error)")
            return
        }
        #expect(exitCode == 1)
    }
}

@Test func shellRunnerTimeoutErrorDescription() throws {
    let error = ShellError.timeout(executable: "/usr/bin/git", args: ["fetch"])
    let description = try #require(error.errorDescription)
    #expect(description.contains("git"))
    #expect(description.contains("timed out"))
}

@Test func shellRunnerCommandFailedErrorDescription() throws {
    let error = ShellError.commandFailed(
        executable: "/usr/bin/git",
        args: ["checkout", "missing"],
        exitCode: 128,
        stderr: "pathspec 'missing' did not match"
    )
    let description = try #require(error.errorDescription)
    #expect(description.contains("git"))
    #expect(description.contains("exit 128"))
    #expect(description.contains("pathspec"))
}
