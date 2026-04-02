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
