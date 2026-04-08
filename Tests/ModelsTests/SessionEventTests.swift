import Testing

@testable import Models

@Test func sessionEventPromptTruncation() {
    let longPrompt = String(repeating: "a", count: 3000)
    let event = SessionEvent(sessionID: "s1", eventType: "UserPromptSubmit", prompt: longPrompt)
    #expect(event.prompt?.count == 2000)
}

@Test func sessionEventDefaults() {
    let event = SessionEvent(sessionID: "s1", eventType: "SessionStart")
    #expect(event.prompt == nil)
    #expect(event.toolName == nil)
    #expect(event.message == nil)
    #expect(!event.id.isEmpty)
}

@Test func sessionEventShortPromptUnchanged() {
    let event = SessionEvent(sessionID: "s1", eventType: "UserPromptSubmit", prompt: "Fix the bug")
    #expect(event.prompt == "Fix the bug")
}
