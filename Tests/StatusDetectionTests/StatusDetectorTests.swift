import Models
import Testing

@testable import StatusDetection

@Test func detectClaudeBusy() {
    let detector = StatusDetector()

    let busy1 = detector.detect(content: "Processing... ctrl+c to interrupt", tool: .claude)
    #expect(busy1 == .running)

    let busy2 = detector.detect(content: "⠙ Working on your request", tool: .claude)
    #expect(busy2 == .running)
}

@Test func detectClaudeWaiting() {
    let detector = StatusDetector()

    let waiting = detector.detect(content: "Yes, allow once\nNo, deny once", tool: .claude)
    #expect(waiting == .waiting)
}

@Test func detectClaudeIdle() {
    let detector = StatusDetector()

    let idle = detector.detect(content: "❯ ", tool: .claude)
    #expect(idle == .idle)
}

@Test func detectShellIdle() {
    let detector = StatusDetector()

    let idle = detector.detect(content: "user@host ~ $", tool: .shell)
    #expect(idle == .idle)
}

@Test func detectGeminiBusy() {
    let detector = StatusDetector()
    let busy = detector.detect(content: "Working...", tool: .gemini)
    #expect(busy == .running)
}

@Test func detectGeminiSpinner() {
    let detector = StatusDetector()
    let busy = detector.detect(content: "⠙ Processing files", tool: .gemini)
    #expect(busy == .running)
}

@Test func detectGeminiWaiting() {
    let detector = StatusDetector()
    let waiting = detector.detect(content: "Action Required\nAllow once", tool: .gemini)
    #expect(waiting == .waiting)
}

@Test func detectGeminiIdle() {
    let detector = StatusDetector()
    let idle = detector.detect(content: "Type your message", tool: .gemini)
    #expect(idle == .idle)
}

@Test func detectGeminiLineStartIdle() {
    let detector = StatusDetector()
    let idle = detector.detect(content: "> ", tool: .gemini)
    #expect(idle == .idle)
}

@Test func detectCodexBusy() {
    let detector = StatusDetector()
    let busy = detector.detect(content: "Working (5s \u{2022} Esc to interrupt)", tool: .codex)
    #expect(busy == .running)
}

@Test func detectCodexWaiting() {
    let detector = StatusDetector()
    let waiting = detector.detect(content: "Would you like to run the following command?\nYes, proceed", tool: .codex)
    #expect(waiting == .waiting)
}

@Test func detectCodexIdle() {
    let detector = StatusDetector()
    let idle = detector.detect(content: "Ask Codex to do anything", tool: .codex)
    #expect(idle == .idle)
}

@Test func detectCodexApprovalNeeded() {
    let detector = StatusDetector()
    let waiting = detector.detect(content: "server-name needs your approval.", tool: .codex)
    #expect(waiting == .waiting)
}
