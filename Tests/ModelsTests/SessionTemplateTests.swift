import Testing

@testable import Models

@Test func templateResolvedPromptWithTitle() {
    let template = SessionTemplate(name: "Test", initialPromptTemplate: "Fix: {title}")
    let result = template.resolvedPrompt(title: "login bug")
    #expect(result == "Fix: login bug")
}

@Test func templateResolvedPromptWithIssue() {
    let template = SessionTemplate(
        name: "Test",
        initialPromptTemplate: "Implement {issue}: {title}"
    )
    let result = template.resolvedPrompt(title: "Add auth", issueNumber: 42, issueTitle: "Auth feature")
    #expect(result == "Implement #42: Auth feature: Add auth")
}

@Test func templateResolvedPromptNoPlaceholders() {
    let template = SessionTemplate(name: "Test", initialPromptTemplate: "Do the thing")
    let result = template.resolvedPrompt(title: "ignored")
    #expect(result == "Do the thing")
}

@Test func templateResolvedPromptEmptyTemplate() {
    let template = SessionTemplate(name: "Test", initialPromptTemplate: "")
    let result = template.resolvedPrompt(title: "anything")
    #expect(result.isEmpty)
}

@Test func templateBuiltInCount() {
    #expect(SessionTemplate.builtIn.count == 3)
}

@Test func templateDefaults() {
    let template = SessionTemplate(name: "Test")
    #expect(template.tool == .claude)
    #expect(template.useWorktree == true)
    #expect(template.permissionMode == .default)
    #expect(template.initialPromptTemplate.isEmpty)
    #expect(template.projectID == nil)
    #expect(!template.id.isEmpty)
}
