import Foundation
import Testing

@testable import Models

@Test func claudeProfileHasHooksEnabled() {
    #expect(AgentProfile.claude.hookEnabled)
    #expect(AgentProfile.claude.id == "claude")
    #expect(AgentProfile.claude.name == "Claude Code")
}

@Test func shellProfileHasHooksDisabled() {
    #expect(!AgentProfile.shell.hookEnabled)
    #expect(AgentProfile.shell.id == "shell")
}

@Test func builtInProfileCount() {
    #expect(AgentProfile.builtIn.count == 4)
}

@Test func defaultProfileForClaude() {
    let profile = AgentProfile.defaultProfile(for: .claude)
    #expect(profile.id == "claude")
    #expect(profile.hookEnabled)
    #expect(!profile.runningPatterns.isEmpty)
}

@Test func defaultProfileForShell() {
    let profile = AgentProfile.defaultProfile(for: .shell)
    #expect(profile.id == "shell")
    #expect(!profile.hookEnabled)
}

@Test func defaultProfileForCustom() {
    let profile = AgentProfile.defaultProfile(for: .custom("aider"))
    #expect(profile.id == "aider")
    #expect(profile.command == "aider")
    #expect(!profile.hookEnabled)
}

@Test func claudeProfileHasAllPatternTypes() {
    let profile = AgentProfile.claude
    #expect(!profile.runningPatterns.isEmpty)
    #expect(!profile.waitingPatterns.isEmpty)
    #expect(!profile.idlePatterns.isEmpty)
    #expect(!profile.lineStartIdlePatterns.isEmpty)
    #expect(!profile.spinnerChars.isEmpty)
}

@Test func agentProfileJSONDecoding() throws {
    let json = """
        {
            "id": "aider",
            "name": "Aider",
            "command": "aider",
            "arguments": ["--watch"],
            "runningPatterns": ["Applying edit"],
            "waitingPatterns": ["Add these files?"],
            "idlePatterns": ["aider>"],
            "lineStartIdlePatterns": [],
            "spinnerChars": [],
            "hookEnabled": false,
            "icon": "terminal.fill"
        }
        """
    let data = try #require(json.data(using: .utf8))
    let profile = try JSONDecoder().decode(AgentProfile.self, from: data)
    #expect(profile.id == "aider")
    #expect(profile.name == "Aider")
    #expect(profile.arguments == ["--watch"])
    #expect(profile.runningPatterns == ["Applying edit"])
    #expect(!profile.hookEnabled)
}
