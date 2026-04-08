import Testing

@testable import Models
@testable import StatusDetection

@Test func detectWithClaudeProfileMatchesBusyPattern() {
    let detector = StatusDetector()
    let content = "Some output\nctrl+c to interrupt\nmore stuff"
    let result = detector.detect(content: content, profile: .claude)
    #expect(result == .running)
}

@Test func detectWithClaudeProfileMatchesWaiting() {
    let detector = StatusDetector()
    let content = "Do you approve?\nYes, allow once\nNo, deny once"
    let result = detector.detect(content: content, profile: .claude)
    #expect(result == .waiting)
}

@Test func detectWithClaudeProfileMatchesIdle() {
    let detector = StatusDetector()
    let content = "How can I help you today?"
    let result = detector.detect(content: content, profile: .claude)
    #expect(result == .idle)
}

@Test func detectWithShellProfileIdleOnPrompt() {
    let detector = StatusDetector()
    let content = "user@host:~$ "
    let result = detector.detect(content: content, profile: .shell)
    #expect(result == .idle)
}

@Test func detectWithShellProfileRunningOnOutput() {
    let detector = StatusDetector()
    let content = "compiling main.swift..."
    let result = detector.detect(content: content, profile: .shell)
    // Shell has no running patterns, so non-idle = .running fallback
    #expect(result == .running)
}

@Test func detectWithCustomProfilePatterns() {
    let detector = StatusDetector()
    let profile = AgentProfile(
        id: "test-agent",
        name: "Test",
        command: "test",
        runningPatterns: ["WORKING"],
        waitingPatterns: ["CONFIRM?"],
        idlePatterns: ["READY>"]
    )

    #expect(detector.detect(content: "WORKING on task", profile: profile) == .running)
    #expect(detector.detect(content: "Please CONFIRM?", profile: profile) == .waiting)
    #expect(detector.detect(content: "READY>", profile: profile) == .idle)
}

@Test func detectWithCustomProfileSpinner() {
    let detector = StatusDetector()
    let profile = AgentProfile(
        id: "spinner-test",
        name: "Test",
        command: "test",
        spinnerChars: ["⣾", "⣽"]
    )
    let result = detector.detect(content: "Loading ⣾", profile: profile)
    #expect(result == .running)
}

@Test func profileDetectMatchesToolDetect() {
    // Verify backwards compatibility: profile-based detection produces
    // the same results as tool-based detection for built-in profiles
    let detector = StatusDetector()

    let claudeContent = "ctrl+c to interrupt"
    #expect(
        detector.detect(content: claudeContent, tool: .claude)
            == detector.detect(content: claudeContent, profile: .claude)
    )

    let waitContent = "Yes, allow once"
    #expect(
        detector.detect(content: waitContent, tool: .claude)
            == detector.detect(content: waitContent, profile: .claude)
    )

    let shellContent = "user@host:~$ "
    #expect(
        detector.detect(content: shellContent, tool: .shell)
            == detector.detect(content: shellContent, profile: .shell)
    )
}
