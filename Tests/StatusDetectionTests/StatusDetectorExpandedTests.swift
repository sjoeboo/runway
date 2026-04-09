import Foundation
import Models
import Testing

@testable import StatusDetection

// MARK: - Additional Claude Detection Patterns

@Test func detectClaudeTokenCountNotBusy() {
    // Token counts appear in completion summaries — should not trigger running status
    let detector = StatusDetector()
    let result = detector.detect(content: "Input: 5.2k tokens", tool: .claude)
    #expect(result == nil)
}

@Test func detectClaudeCostLineNotBusy() {
    // Cost lines appear in completion summaries — should not trigger running status
    let detector = StatusDetector()
    let result = detector.detect(content: "cost: $0.0042", tool: .claude)
    #expect(result == nil)
}

@Test func detectClaudeBusyWorkingMessage() {
    let detector = StatusDetector()
    let result = detector.detect(content: "Working...", tool: .claude)
    #expect(result == .running)
}

@Test func detectClaudeBusyOutputMarker() {
    let detector = StatusDetector()
    // The ⎿ character is used in Claude's output rendering
    let result = detector.detect(content: "⎿ Updated src/main.swift", tool: .claude)
    #expect(result == .running)
}

@Test func detectClaudeBusySpinnerChars() {
    let detector = StatusDetector()
    let spinners = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    for spinner in spinners {
        let result = detector.detect(content: "\(spinner) Processing...", tool: .claude)
        #expect(result == .running, "Spinner \(spinner) should indicate running")
    }
}

// MARK: - Claude Waiting Patterns

@Test func detectClaudeWaitingPermissionVariants() {
    let detector = StatusDetector()

    let patterns = [
        "Yes, always allow",
        "No, and tell Claude",
        "approve?",
        "Approve?",
        "(Y/n)",
        "(y/N)",
        "Allow?",
        "Try again",
        "Do you want to",
    ]

    for pattern in patterns {
        let result = detector.detect(content: pattern, tool: .claude)
        #expect(result == .waiting, "Pattern '\(pattern)' should indicate waiting")
    }
}

// MARK: - Claude Idle Patterns

@Test func detectClaudeIdlePromptVariants() {
    let detector = StatusDetector()

    let patterns = [
        "How can I help",
        "What would you like to do",
        "Enter your prompt",
        "$ ",
    ]

    for pattern in patterns {
        let result = detector.detect(content: pattern, tool: .claude)
        #expect(result == .idle, "Pattern '\(pattern)' should indicate idle")
    }
}

@Test func detectWaitingWithSpecificPatterns() {
    let detector = StatusDetector()
    // "What would you like to do" is idle (not waiting) — the waiting patterns
    // are now more specific to avoid matching the idle prompt.
    let idleResult = detector.detect(content: "What would you like to do", tool: .claude)
    #expect(idleResult == .idle)

    // Specific waiting patterns should still detect as waiting
    let waitingResult = detector.detect(content: "What would you like me to do?", tool: .claude)
    #expect(waitingResult == .waiting)
}

@Test func detectClaudeNoMatch() {
    let detector = StatusDetector()
    // Random content that doesn't match any pattern
    let result = detector.detect(content: "some random output text", tool: .claude)
    #expect(result == nil)
}

// MARK: - Shell Detection

@Test func detectShellPromptVariants() {
    let detector = StatusDetector()

    let prompts = [
        "user@host ~ $",
        "➜ ~/code %",
        "root@server #",
        "~/project ❯",
    ]

    for prompt in prompts {
        let result = detector.detect(content: prompt, tool: .shell)
        #expect(result == .idle, "Shell prompt '\(prompt)' should indicate idle")
    }
}

@Test func detectShellRunning() {
    let detector = StatusDetector()
    let result = detector.detect(content: "Building project...\nCompiling file 3/10", tool: .shell)
    #expect(result == .running)
}

// MARK: - Custom Tool Detection

@Test func detectCustomToolFallsBackToShellDetection() {
    let detector = StatusDetector()
    let idle = detector.detect(content: "user@host $", tool: .custom("aider"))
    #expect(idle == .idle)

    let running = detector.detect(content: "Generating response...", tool: .custom("aider"))
    #expect(running == .running)
}

// MARK: - ANSI Stripping

@Test func detectWithANSIEscapes() {
    let detector = StatusDetector()
    // Content with ANSI escape codes wrapping a busy pattern
    let ansiContent = "\u{1B}[32mctrl+c to interrupt\u{1B}[0m"
    let result = detector.detect(content: ansiContent, tool: .claude)
    #expect(result == .running)
}

@Test func detectWithANSIMoveCursor() {
    let detector = StatusDetector()
    let content = "\u{1B}[2J\u{1B}[H❯ "
    let result = detector.detect(content: content, tool: .claude)
    #expect(result == .idle)
}

// MARK: - Multi-line Content

@Test func detectUsesLastLines() {
    let detector = StatusDetector()
    // Old content at top (idle), new content at bottom (busy)
    let content = """
        ❯ help me

        I'll help you with that.

        Working...
        ⠙ Reading files
        ctrl+c to interrupt
        """
    let result = detector.detect(content: content, tool: .claude)
    #expect(result == .running)
}

@Test func detectPrioritizeBusyOverIdle() {
    let detector = StatusDetector()
    // Content with both busy and idle indicators — busy should win
    let content = "❯ ctrl+c to interrupt"
    let result = detector.detect(content: content, tool: .claude)
    #expect(result == .running)
}
