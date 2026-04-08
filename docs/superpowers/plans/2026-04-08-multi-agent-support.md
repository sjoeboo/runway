# Multi-Agent Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class Gemini CLI and Codex support with data-driven hook injection and a Happy wrapper toggle.

**Architecture:** Extend the `Tool` enum with `.gemini` and `.codex` cases, add built-in `AgentProfile` definitions with terminal detection patterns, generalize `HookInjector` to accept a `HookInjectionConfig` per agent, add `useHappy` to `Session` for wrapping agents with Happy, and update the New Session dialog.

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/Models/Session.swift` | Modify | Add `.gemini`, `.codex` to Tool enum; add `useHappy` to Session; add Tool convenience properties; refactor PermissionMode |
| `Sources/Models/AgentProfile.swift` | Modify | Add `.gemini`, `.codex` built-in profiles; update `builtIn` and `defaultProfile(for:)` |
| `Sources/Models/NewSessionRequest.swift` | Modify | Add `useHappy: Bool` parameter |
| `Sources/Models/HookEvent.swift` | Modify | Add Gemini/Codex event types to `HookEventType` |
| `Sources/StatusDetection/HookInjectionConfig.swift` | Create | `HookInjectionConfig` struct with built-in configs per agent |
| `Sources/StatusDetection/HookInjector.swift` | Modify | Generalize to accept `HookInjectionConfig`; add TOML pre-step |
| `Sources/Persistence/Records.swift` | Modify | Encode/decode `.gemini`, `.codex`, `useHappy` |
| `Sources/Persistence/Database.swift` | Modify | Migration v14 for `useHappy` column |
| `Sources/App/RunwayStore.swift` | Modify | Multi-agent hook injection at startup; Happy wrapping in `startTmuxSession`; event mapping |
| `Sources/Views/Shared/NewSessionDialog.swift` | Modify | Happy toggle; expand permission/prompt visibility |
| `Tests/ModelsTests/SessionTests.swift` | Modify | Tests for new Tool cases, `useHappy`, `cliFlags(for:)` |
| `Tests/ModelsTests/AgentProfileTests.swift` | Modify | Tests for new profiles |
| `Tests/StatusDetectionTests/HookInjectorTests.swift` | Modify | Tests for generalized injector with configs |
| `Tests/StatusDetectionTests/StatusDetectorTests.swift` | Modify | Tests for Gemini/Codex buffer detection |
| `Tests/PersistenceTests/DatabaseTests.swift` | Modify | Tests for `useHappy` persistence |

---

### Task 1: Extend Tool Enum with Gemini and Codex

**Files:**
- Modify: `Sources/Models/Session.swift:111-164`
- Test: `Tests/ModelsTests/SessionTests.swift`

- [ ] **Step 1: Write failing tests for new Tool cases**

Add to `Tests/ModelsTests/SessionTests.swift`:

```swift
@Test func geminiToolProperties() {
    #expect(Tool.gemini.displayName == "Gemini CLI")
    #expect(Tool.gemini.command == "gemini")
}

@Test func codexToolProperties() {
    #expect(Tool.codex.displayName == "Codex")
    #expect(Tool.codex.command == "codex")
}

@Test func toolSupportsPermissionModes() {
    #expect(Tool.claude.supportsPermissionModes == true)
    #expect(Tool.gemini.supportsPermissionModes == true)
    #expect(Tool.codex.supportsPermissionModes == true)
    #expect(Tool.shell.supportsPermissionModes == false)
    #expect(Tool.custom("aider").supportsPermissionModes == false)
}

@Test func toolSupportsHappy() {
    #expect(Tool.claude.supportsHappy == true)
    #expect(Tool.gemini.supportsHappy == true)
    #expect(Tool.codex.supportsHappy == true)
    #expect(Tool.shell.supportsHappy == false)
}

@Test func toolSupportsInitialPrompt() {
    #expect(Tool.claude.supportsInitialPrompt == true)
    #expect(Tool.gemini.supportsInitialPrompt == true)
    #expect(Tool.codex.supportsInitialPrompt == true)
    #expect(Tool.shell.supportsInitialPrompt == false)
}

@Test func toolIsAgent() {
    #expect(Tool.claude.isAgent == true)
    #expect(Tool.gemini.isAgent == true)
    #expect(Tool.codex.isAgent == true)
    #expect(Tool.shell.isAgent == false)
    #expect(Tool.custom("aider").isAgent == true)
}

@Test func toolCodableRoundTrip() throws {
    let tools: [Tool] = [.claude, .gemini, .codex, .shell, .custom("aider")]
    for tool in tools {
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(Tool.self, from: data)
        #expect(decoded == tool)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTests`
Expected: Compilation errors — `Tool` has no member `gemini` or `codex`

- [ ] **Step 3: Implement Tool enum changes**

In `Sources/Models/Session.swift`, add cases to the `Tool` enum:

```swift
public enum Tool: Codable, Sendable, Hashable {
    case claude
    case gemini
    case codex
    case shell
    case custom(String)

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini CLI"
        case .codex: "Codex"
        case .shell: "Shell"
        case .custom(let name): name
        }
    }

    public var command: String {
        switch self {
        case .claude: "claude"
        case .gemini: "gemini"
        case .codex: "codex"
        case .shell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        case .custom(let name): name
        }
    }
}
```

Add convenience properties after the closing brace of `Tool`:

```swift
extension Tool {
    public var supportsPermissionModes: Bool {
        switch self {
        case .claude, .gemini, .codex: true
        default: false
        }
    }

    public var supportsInitialPrompt: Bool {
        switch self {
        case .claude, .gemini, .codex: true
        default: false
        }
    }

    public var supportsHappy: Bool {
        switch self {
        case .claude, .gemini, .codex: true
        default: false
        }
    }

    public var isAgent: Bool {
        switch self {
        case .shell: false
        default: true
        }
    }
}
```

Update Codable conformance — add cases to `init(from:)` and `encode(to:)`:

```swift
extension Tool {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "claude": self = .claude
        case "gemini": self = .gemini
        case "codex": self = .codex
        case "shell": self = .shell
        default:
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? type
            self = .custom(name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .claude:
            try container.encode("claude", forKey: .type)
        case .gemini:
            try container.encode("gemini", forKey: .type)
        case .codex:
            try container.encode("codex", forKey: .type)
        case .shell:
            try container.encode("shell", forKey: .type)
        case .custom(let name):
            try container.encode("custom", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionTests`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/Session.swift Tests/ModelsTests/SessionTests.swift
git commit -m "feat: add gemini and codex to Tool enum with convenience properties"
```

---

### Task 2: Refactor PermissionMode for Agent-Specific CLI Flags

**Files:**
- Modify: `Sources/Models/Session.swift:64-86`
- Test: `Tests/ModelsTests/SessionTests.swift`

- [ ] **Step 1: Write failing tests for `cliFlags(for:)`**

Add to `Tests/ModelsTests/SessionTests.swift`:

```swift
@Test func permissionModeCliFlagsForClaude() {
    #expect(PermissionMode.default.cliFlags(for: .claude) == [])
    #expect(PermissionMode.acceptEdits.cliFlags(for: .claude) == ["--accept-edits"])
    #expect(PermissionMode.bypassAll.cliFlags(for: .claude) == ["--dangerously-skip-permissions"])
}

@Test func permissionModeCliFlagsForGemini() {
    #expect(PermissionMode.default.cliFlags(for: .gemini) == [])
    #expect(PermissionMode.acceptEdits.cliFlags(for: .gemini) == ["--yolo"])
    #expect(PermissionMode.bypassAll.cliFlags(for: .gemini) == ["--yolo"])
}

@Test func permissionModeCliFlagsForCodex() {
    #expect(PermissionMode.default.cliFlags(for: .codex) == [])
    #expect(PermissionMode.acceptEdits.cliFlags(for: .codex) == ["--full-auto"])
    #expect(PermissionMode.bypassAll.cliFlags(for: .codex) == ["--yolo"])
}

@Test func permissionModeCliFlagsForShell() {
    #expect(PermissionMode.acceptEdits.cliFlags(for: .shell) == [])
    #expect(PermissionMode.bypassAll.cliFlags(for: .shell) == [])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTests`
Expected: Compilation error — `cliFlags(for:)` doesn't exist

- [ ] **Step 3: Replace `cliFlags` with `cliFlags(for:)`**

In `Sources/Models/Session.swift`, replace the `PermissionMode` `cliFlags` computed property:

```swift
public enum PermissionMode: String, Codable, Sendable, CaseIterable {
    case `default` = "default"
    case acceptEdits = "accept_edits"
    case bypassAll = "bypass_all"

    public var displayName: String {
        switch self {
        case .default: "Default"
        case .acceptEdits: "Accept Edits"
        case .bypassAll: "Bypass All"
        }
    }

    public func cliFlags(for tool: Tool) -> [String] {
        switch (self, tool) {
        case (.default, _): []
        case (.acceptEdits, .claude): ["--accept-edits"]
        case (.acceptEdits, .gemini): ["--yolo"]
        case (.acceptEdits, .codex): ["--full-auto"]
        case (.bypassAll, .claude): ["--dangerously-skip-permissions"]
        case (.bypassAll, .gemini): ["--yolo"]
        case (.bypassAll, .codex): ["--yolo"]
        default: []
        }
    }
}
```

- [ ] **Step 4: Fix compilation — update all call sites of `.cliFlags`**

In `Sources/App/RunwayStore.swift:444`, change:
```swift
// Before:
parts.append(contentsOf: session.permissionMode.cliFlags)
// After:
parts.append(contentsOf: session.permissionMode.cliFlags(for: session.tool))
```

Search for any other references to `.cliFlags` (without parameters) and update them. There should only be the one call site in `startTmuxSession`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SessionTests`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/Session.swift Sources/App/RunwayStore.swift
git commit -m "feat: agent-specific permission mode CLI flag mapping"
```

---

### Task 3: Add `useHappy` to Session and NewSessionRequest

**Files:**
- Modify: `Sources/Models/Session.swift:4-62`
- Modify: `Sources/Models/NewSessionRequest.swift`
- Test: `Tests/ModelsTests/SessionTests.swift`

- [ ] **Step 1: Write failing tests for `useHappy`**

Add to `Tests/ModelsTests/SessionTests.swift`:

```swift
@Test func sessionUseHappyDefaultsFalse() {
    let session = Session(title: "test", path: "/tmp")
    #expect(session.useHappy == false)
}

@Test func sessionUseHappyPreserved() {
    let session = Session(title: "test", path: "/tmp", useHappy: true)
    #expect(session.useHappy == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTests`
Expected: Compilation error — `useHappy` doesn't exist on Session

- [ ] **Step 3: Add `useHappy` to Session**

In `Sources/Models/Session.swift`, add to the `Session` struct properties (after `permissionMode`):

```swift
public var useHappy: Bool
```

Add to `init` parameters (after `permissionMode: PermissionMode = .default`):

```swift
useHappy: Bool = false,
```

Add to `init` body (after `self.permissionMode = permissionMode`):

```swift
self.useHappy = useHappy
```

- [ ] **Step 4: Add `useHappy` to NewSessionRequest**

In `Sources/Models/NewSessionRequest.swift`, add to properties (after `permissionMode`):

```swift
public let useHappy: Bool
```

Add to `init` parameters (after `permissionMode: PermissionMode = .default`):

```swift
useHappy: Bool = false,
```

Add to `init` body (after `self.permissionMode = permissionMode`):

```swift
self.useHappy = useHappy
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SessionTests`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/Session.swift Sources/Models/NewSessionRequest.swift
git commit -m "feat: add useHappy field to Session and NewSessionRequest"
```

---

### Task 4: Add Gemini and Codex Built-in Agent Profiles

**Files:**
- Modify: `Sources/Models/AgentProfile.swift:54-150`
- Test: `Tests/ModelsTests/AgentProfileTests.swift`

- [ ] **Step 1: Write failing tests for new profiles**

Add to `Tests/ModelsTests/AgentProfileTests.swift`:

```swift
@Test func geminiProfileProperties() {
    let profile = AgentProfile.gemini
    #expect(profile.id == "gemini")
    #expect(profile.name == "Gemini CLI")
    #expect(profile.command == "gemini")
    #expect(profile.hookEnabled == true)
    #expect(profile.icon == "diamond.fill")
    #expect(!profile.runningPatterns.isEmpty)
    #expect(!profile.waitingPatterns.isEmpty)
    #expect(!profile.idlePatterns.isEmpty)
    #expect(!profile.spinnerChars.isEmpty)
}

@Test func codexProfileProperties() {
    let profile = AgentProfile.codex
    #expect(profile.id == "codex")
    #expect(profile.name == "Codex")
    #expect(profile.command == "codex")
    #expect(profile.hookEnabled == true)
    #expect(profile.icon == "cpu")
    #expect(profile.arguments == ["--no-alt-screen"])
    #expect(!profile.runningPatterns.isEmpty)
    #expect(!profile.waitingPatterns.isEmpty)
    #expect(!profile.idlePatterns.isEmpty)
}

@Test func builtInProfileCountIncludesNewAgents() {
    #expect(AgentProfile.builtIn.count == 4)  // claude, gemini, codex, shell
}

@Test func defaultProfileForGemini() {
    let profile = AgentProfile.defaultProfile(for: .gemini)
    #expect(profile.id == "gemini")
    #expect(profile.hookEnabled == true)
}

@Test func defaultProfileForCodex() {
    let profile = AgentProfile.defaultProfile(for: .codex)
    #expect(profile.id == "codex")
    #expect(profile.hookEnabled == true)
    #expect(profile.arguments == ["--no-alt-screen"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentProfileTests`
Expected: Compilation errors — no `.gemini` or `.codex` on AgentProfile

- [ ] **Step 3: Add built-in profiles**

In `Sources/Models/AgentProfile.swift`, add after the `.shell` profile:

```swift
/// Gemini CLI — Google's AI coding agent with hook support.
public static let gemini = AgentProfile(
    id: "gemini",
    name: "Gemini CLI",
    command: "gemini",
    arguments: [],
    runningPatterns: ["Working..."],
    waitingPatterns: [
        "Action Required",
        "Apply this change?",
        "Allow execution of",
        "Allow once",
        "Allow for this session",
        "Do you want to proceed?",
        "Answer Questions",
    ],
    idlePatterns: ["Type your message"],
    lineStartIdlePatterns: ["> "],
    spinnerChars: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    hookEnabled: true,
    icon: "diamond.fill"
)

/// Codex — OpenAI's AI coding agent. Uses --no-alt-screen for buffer detection.
public static let codex = AgentProfile(
    id: "codex",
    name: "Codex",
    command: "codex",
    arguments: ["--no-alt-screen"],
    runningPatterns: ["Working", "Esc to interrupt"],
    waitingPatterns: [
        "Would you like to run",
        "Would you like to make",
        "Would you like to grant",
        "Yes, proceed",
        "needs your approval",
        "Implement this plan?",
    ],
    idlePatterns: ["Ask Codex to do anything"],
    lineStartIdlePatterns: [],
    spinnerChars: [],
    hookEnabled: true,
    icon: "cpu"
)
```

Update `builtIn`:

```swift
public static let builtIn: [AgentProfile] = [.claude, .gemini, .codex, .shell]
```

Update `defaultProfile(for:)`:

```swift
public static func defaultProfile(for tool: Tool) -> AgentProfile {
    switch tool {
    case .claude: return .claude
    case .gemini: return .gemini
    case .codex: return .codex
    case .shell: return .shell
    case .custom(let name):
        return AgentProfile(
            id: name, name: name, command: name,
            idlePatterns: ["$", "%", "#", "❯"],
            icon: "terminal.fill"
        )
    }
}
```

- [ ] **Step 4: Update existing test assertion**

In `Tests/ModelsTests/AgentProfileTests.swift`, update the `builtInProfileCount` test:

```swift
@Test func builtInProfileCount() {
    #expect(AgentProfile.builtIn.count == 4)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AgentProfileTests`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/AgentProfile.swift Tests/ModelsTests/AgentProfileTests.swift
git commit -m "feat: add built-in Gemini CLI and Codex agent profiles"
```

---

### Task 5: Add Gemini/Codex Hook Event Types

**Files:**
- Modify: `Sources/Models/HookEvent.swift:51-58`
- Test: `Tests/ModelsTests/HookEventTests.swift`

- [ ] **Step 1: Read existing HookEvent tests**

Read `Tests/ModelsTests/HookEventTests.swift` to understand the test pattern.

- [ ] **Step 2: Write failing tests for new event types**

Add to `Tests/ModelsTests/HookEventTests.swift`:

```swift
@Test func geminiBeforeAgentEventDecodes() throws {
    let json = """
        {"session_id": "s1", "hook_event_name": "BeforeAgent"}
        """
    let data = try #require(json.data(using: .utf8))
    let event = try JSONDecoder().decode(HookEvent.self, from: data)
    #expect(event.event == .beforeAgent)
}

@Test func geminiAfterAgentEventDecodes() throws {
    let json = """
        {"session_id": "s1", "hook_event_name": "AfterAgent"}
        """
    let data = try #require(json.data(using: .utf8))
    let event = try JSONDecoder().decode(HookEvent.self, from: data)
    #expect(event.event == .afterAgent)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter HookEventTests`
Expected: Decoding error — no `BeforeAgent` or `AfterAgent` case

- [ ] **Step 4: Add event types**

In `Sources/Models/HookEvent.swift`, add to the `HookEventType` enum:

```swift
public enum HookEventType: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case stop = "Stop"
    case userPromptSubmit = "UserPromptSubmit"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    // Gemini CLI events
    case beforeAgent = "BeforeAgent"
    case afterAgent = "AfterAgent"
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter HookEventTests`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/HookEvent.swift Tests/ModelsTests/HookEventTests.swift
git commit -m "feat: add BeforeAgent and AfterAgent hook event types for Gemini"
```

---

### Task 6: Buffer Detection Tests for Gemini and Codex

**Files:**
- Test: `Tests/StatusDetectionTests/StatusDetectorTests.swift`

- [ ] **Step 1: Write tests for Gemini buffer detection**

Add to `Tests/StatusDetectionTests/StatusDetectorTests.swift`:

```swift
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
```

- [ ] **Step 2: Write tests for Codex buffer detection**

Add to the same file:

```swift
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
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `swift test --filter StatusDetectorTests`
Expected: All pass (the `StatusDetector` already uses `AgentProfile.defaultProfile(for:)`, so the new profiles provide the patterns automatically)

- [ ] **Step 4: Commit**

```bash
git add Tests/StatusDetectionTests/StatusDetectorTests.swift
git commit -m "test: add buffer detection tests for Gemini CLI and Codex"
```

---

### Task 7: Create HookInjectionConfig

**Files:**
- Create: `Sources/StatusDetection/HookInjectionConfig.swift`

- [ ] **Step 1: Create the config struct**

Create `Sources/StatusDetection/HookInjectionConfig.swift`:

```swift
import Foundation

/// Describes how to inject Runway lifecycle hooks into an agent's configuration.
///
/// Each agent has its own config directory, settings file, and event vocabulary.
/// The `HookInjector` reads this config to perform agent-agnostic injection.
public struct HookInjectionConfig: Sendable {
    /// Agent identifier (e.g., "claude", "gemini", "codex").
    public let agentID: String
    /// Path to the agent's config directory (e.g., "~/.claude").
    public let configDir: String
    /// Settings filename within configDir (e.g., "settings.json", "hooks.json").
    public let settingsFile: String
    /// Events to subscribe to and their optional matcher patterns.
    public let events: [(event: String, matcher: String?)]
    /// HTTP header key for session ID.
    public let headerKey: String
    /// Environment variable name for session ID.
    public let envVar: String
    /// Hook timeout in seconds.
    public let timeout: Int
    /// Steps to run before injecting hooks (e.g., enabling feature flags).
    public let preSteps: [PreInjectionStep]

    public init(
        agentID: String,
        configDir: String,
        settingsFile: String,
        events: [(event: String, matcher: String?)],
        headerKey: String = "X-Runway-Session-Id",
        envVar: String = "RUNWAY_SESSION_ID",
        timeout: Int = 5,
        preSteps: [PreInjectionStep] = []
    ) {
        self.agentID = agentID
        self.configDir = configDir
        self.settingsFile = settingsFile
        self.events = events
        self.headerKey = headerKey
        self.envVar = envVar
        self.timeout = timeout
        self.preSteps = preSteps
    }
}

/// A pre-injection step to run before hook injection.
public enum PreInjectionStep: Sendable {
    /// Ensure a key=value exists in a TOML config file under a given section.
    case ensureTOMLFlag(file: String, section: String, key: String, value: String)
}

// MARK: - Built-in Configs

extension HookInjectionConfig {
    private static let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

    /// Claude Code — hooks in ~/.claude/settings.json
    public static let claude = HookInjectionConfig(
        agentID: "claude",
        configDir: "\(homeDir)/.claude",
        settingsFile: "settings.json",
        events: [
            ("SessionStart", nil),
            ("UserPromptSubmit", nil),
            ("Stop", nil),
            ("PermissionRequest", nil),
            ("Notification", "permission_prompt|elicitation_dialog"),
            ("SessionEnd", nil),
        ]
    )

    /// Gemini CLI — hooks in ~/.gemini/settings.json (same format as Claude)
    public static let gemini = HookInjectionConfig(
        agentID: "gemini",
        configDir: "\(homeDir)/.gemini",
        settingsFile: "settings.json",
        events: [
            ("SessionStart", nil),
            ("SessionEnd", nil),
            ("BeforeAgent", nil),
            ("AfterAgent", nil),
            ("Notification", nil),
        ]
    )

    /// Codex — hooks in ~/.codex/hooks.json, requires feature flag in config.toml
    public static let codex = HookInjectionConfig(
        agentID: "codex",
        configDir: "\(homeDir)/.codex",
        settingsFile: "hooks.json",
        events: [
            ("SessionStart", nil),
            ("UserPromptSubmit", nil),
            ("Stop", nil),
        ],
        preSteps: [
            .ensureTOMLFlag(file: "config.toml", section: "features", key: "codex_hooks", value: "true"),
        ]
    )

    /// All built-in hook injection configs.
    public static let allBuiltIn: [HookInjectionConfig] = [.claude, .gemini, .codex]
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/StatusDetection/HookInjectionConfig.swift
git commit -m "feat: add HookInjectionConfig for data-driven hook injection"
```

---

### Task 8: Generalize HookInjector to Accept Config

**Files:**
- Modify: `Sources/StatusDetection/HookInjector.swift`
- Test: `Tests/StatusDetectionTests/HookInjectorTests.swift`

- [ ] **Step 1: Write failing tests for config-based injection**

Add to `Tests/StatusDetectionTests/HookInjectorTests.swift`:

```swift
@Test func hookInjectorInjectWithConfig() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let config = HookInjectionConfig(
        agentID: "test-agent",
        configDir: tmpDir,
        settingsFile: "settings.json",
        events: [("SessionStart", nil), ("Stop", nil)]
    )

    let injector = HookInjector()
    let installed = try injector.inject(port: 47437, config: config)
    #expect(installed == true)

    let settingsPath = "\(tmpDir)/settings.json"
    let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let hooks = try #require(json["hooks"] as? [String: Any])
    #expect(hooks["SessionStart"] != nil)
    #expect(hooks["Stop"] != nil)
}

@Test func hookInjectorRemoveWithConfig() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let config = HookInjectionConfig(
        agentID: "test-agent",
        configDir: tmpDir,
        settingsFile: "settings.json",
        events: [("SessionStart", nil)]
    )

    let injector = HookInjector()
    try injector.inject(port: 47437, config: config)
    #expect(injector.isInstalled(config: config) == true)

    try injector.remove(config: config)
    #expect(injector.isInstalled(config: config) == false)
}

@Test func hookInjectorGeminiConfig() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let config = HookInjectionConfig(
        agentID: "gemini",
        configDir: tmpDir,
        settingsFile: "settings.json",
        events: [
            ("SessionStart", nil),
            ("SessionEnd", nil),
            ("BeforeAgent", nil),
            ("AfterAgent", nil),
            ("Notification", nil),
        ]
    )

    let injector = HookInjector()
    try injector.inject(port: 47437, config: config)

    let data = try Data(contentsOf: URL(fileURLWithPath: "\(tmpDir)/settings.json"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let hooks = try #require(json["hooks"] as? [String: Any])
    #expect(hooks["BeforeAgent"] != nil)
    #expect(hooks["AfterAgent"] != nil)
}

@Test func hookInjectorCodexPreStepCreatesTOML() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let config = HookInjectionConfig(
        agentID: "codex",
        configDir: tmpDir,
        settingsFile: "hooks.json",
        events: [("SessionStart", nil)],
        preSteps: [
            .ensureTOMLFlag(file: "config.toml", section: "features", key: "codex_hooks", value: "true"),
        ]
    )

    let injector = HookInjector()
    try injector.inject(port: 47437, config: config)

    // Verify TOML file was created with the feature flag
    let tomlPath = "\(tmpDir)/config.toml"
    let tomlContent = try String(contentsOfFile: tomlPath, encoding: .utf8)
    #expect(tomlContent.contains("[features]"))
    #expect(tomlContent.contains("codex_hooks = true"))

    // Verify hooks.json was created
    let hooksPath = "\(tmpDir)/hooks.json"
    #expect(FileManager.default.fileExists(atPath: hooksPath))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HookInjectorTests`
Expected: Compilation errors — `inject(port:config:)` doesn't exist

- [ ] **Step 3: Refactor HookInjector**

Rewrite `Sources/StatusDetection/HookInjector.swift` to accept `HookInjectionConfig`. Keep the existing convenience methods (no `config` parameter) as wrappers that use `HookInjectionConfig.claude`:

```swift
import Foundation
import Models

/// Injects Runway hook entries into AI coding agent configuration files.
///
/// Uses a read-preserve-modify-write pattern to preserve all existing settings
/// and user hooks while adding Runway's HTTP hooks for lifecycle events.
public struct HookInjector: Sendable {
    private static let hookURLTemplate = "http://127.0.0.1:%d/hooks"
    private static let hookURLPrefix = "http://127.0.0.1:"
    private static let hookURLSuffix = "/hooks"

    public init() {}

    // MARK: - Config-Based API

    /// Inject HTTP hooks using a config.
    @discardableResult
    public func inject(port: UInt16 = 47437, config: HookInjectionConfig, force: Bool = false) throws -> Bool {
        // Run pre-injection steps
        try handlePreSteps(config.preSteps, configDir: config.configDir)

        let settingsPath = "\(config.configDir)/\(config.settingsFile)"
        return try withSettingsLock(path: settingsPath) {
            try _inject(port: port, settingsPath: settingsPath, configDir: config.configDir, events: config.events, headerKey: config.headerKey, envVar: config.envVar, timeout: config.timeout, force: force)
        }
    }

    /// Remove Runway hooks using a config.
    public func remove(config: HookInjectionConfig) throws {
        let settingsPath = "\(config.configDir)/\(config.settingsFile)"
        try withSettingsLock(path: settingsPath) {
            var rawSettings = try readSettings(at: settingsPath)
            guard var hooks = rawSettings["hooks"] as? [String: Any] else { return }

            removeExistingHooks(from: &hooks, events: config.events)

            if hooks.isEmpty {
                rawSettings.removeValue(forKey: "hooks")
            } else {
                rawSettings["hooks"] = hooks
            }

            try writeSettings(rawSettings, to: settingsPath, configDir: config.configDir)
        }
    }

    /// Check if hooks are installed for a config.
    public func isInstalled(config: HookInjectionConfig) -> Bool {
        let settingsPath = "\(config.configDir)/\(config.settingsFile)"
        guard let rawSettings = try? readSettings(at: settingsPath),
            let hooks = rawSettings["hooks"] as? [String: Any]
        else { return false }
        return httpHooksInstalled(in: hooks, url: nil, events: config.events)
    }

    // MARK: - Legacy Convenience API (Claude-only)

    /// Inject HTTP hooks into Claude Code settings (convenience wrapper).
    @discardableResult
    public func inject(port: UInt16 = 47437, configDir: String? = nil, force: Bool = false) throws -> Bool {
        var config = HookInjectionConfig.claude
        if let configDir {
            config = HookInjectionConfig(
                agentID: "claude",
                configDir: configDir,
                settingsFile: config.settingsFile,
                events: config.events,
                headerKey: config.headerKey,
                envVar: config.envVar,
                timeout: config.timeout,
                preSteps: config.preSteps
            )
        }
        return try inject(port: port, config: config, force: force)
    }

    /// Remove Runway hooks from Claude Code settings (convenience wrapper).
    public func remove(configDir: String? = nil) throws {
        var config = HookInjectionConfig.claude
        if let configDir {
            config = HookInjectionConfig(
                agentID: "claude",
                configDir: configDir,
                settingsFile: config.settingsFile,
                events: config.events,
                headerKey: config.headerKey,
                envVar: config.envVar,
                timeout: config.timeout,
                preSteps: config.preSteps
            )
        }
        try remove(config: config)
    }

    /// Check if hooks are currently installed (Claude convenience wrapper).
    public func isInstalled(configDir: String? = nil) -> Bool {
        var config = HookInjectionConfig.claude
        if let configDir {
            config = HookInjectionConfig(
                agentID: "claude",
                configDir: configDir,
                settingsFile: config.settingsFile,
                events: config.events,
                headerKey: config.headerKey,
                envVar: config.envVar,
                timeout: config.timeout,
                preSteps: config.preSteps
            )
        }
        return isInstalled(config: config)
    }

    // MARK: - Private Core

    private func _inject(
        port: UInt16, settingsPath: String, configDir: String,
        events: [(event: String, matcher: String?)],
        headerKey: String, envVar: String, timeout: Int,
        force: Bool
    ) throws -> Bool {
        var rawSettings = try readSettings(at: settingsPath)
        var hooks = (rawSettings["hooks"] as? [String: Any]) ?? [:]

        let hookURL = String(format: Self.hookURLTemplate, Int(port))
        if !force && httpHooksInstalled(in: hooks, url: hookURL, events: events) {
            return false
        }

        removeExistingHooks(from: &hooks, events: events)

        let hookEntry: [String: Any] = [
            "type": "http",
            "url": hookURL,
            "headers": [headerKey: "$\(envVar)"],
            "allowedEnvVars": [envVar],
            "timeout": timeout,
        ]

        for config in events {
            hooks[config.event] = mergeHookEvent(
                existing: hooks[config.event],
                matcher: config.matcher,
                hook: hookEntry
            )
        }

        rawSettings["hooks"] = hooks
        try writeSettings(rawSettings, to: settingsPath, configDir: configDir)
        return true
    }

    // MARK: - Pre-Injection Steps

    private func handlePreSteps(_ steps: [PreInjectionStep], configDir: String) throws {
        for step in steps {
            switch step {
            case .ensureTOMLFlag(let file, let section, let key, let value):
                try ensureTOMLFlag(
                    filePath: "\(configDir)/\(file)",
                    configDir: configDir,
                    section: section, key: key, value: value
                )
            }
        }
    }

    /// Ensure a TOML file has a key=value under [section].
    /// Creates the file if it doesn't exist. Appends section/key if missing.
    private func ensureTOMLFlag(filePath: String, configDir: String, section: String, key: String, value: String) throws {
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        let needle = "\(key) = \(value)"
        var content: String
        if FileManager.default.fileExists(atPath: filePath) {
            content = try String(contentsOfFile: filePath, encoding: .utf8)
            if content.contains(needle) { return }  // Already present
            // Check if section exists
            let sectionHeader = "[\(section)]"
            if let range = content.range(of: sectionHeader) {
                // Insert key after section header line
                let insertPoint = content[range.upperBound...].firstIndex(of: "\n").map { content.index(after: $0) } ?? content.endIndex
                content.insert(contentsOf: "\(needle)\n", at: insertPoint)
            } else {
                content.append("\n[\(section)]\n\(needle)\n")
            }
        } else {
            content = "[\(section)]\n\(needle)\n"
        }
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - JSON Operations (unchanged logic)

    private func readSettings(at path: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private func writeSettings(_ settings: [String: Any], to path: String, configDir: String) throws {
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func withSettingsLock<T>(path: String, body: () throws -> T) throws -> T {
        let lockPath = path + ".lock"
        let lockFD = open(lockPath, O_CREAT | O_WRONLY, 0o644)
        guard lockFD >= 0 else { return try body() }
        defer {
            flock(lockFD, LOCK_UN)
            close(lockFD)
        }
        flock(lockFD, LOCK_EX)
        return try body()
    }

    private func httpHooksInstalled(in hooks: [String: Any], url: String?, events: [(event: String, matcher: String?)]) -> Bool {
        for config in events {
            guard let eventData = hooks[config.event] else { return false }
            if !eventContainsRunwayHook(eventData, expectedURL: url) { return false }
        }
        return true
    }

    private func eventContainsRunwayHook(_ eventData: Any, expectedURL: String? = nil) -> Bool {
        let blocks: [[String: Any]]
        if let single = eventData as? [String: Any] {
            blocks = [single]
        } else if let array = eventData as? [[String: Any]] {
            blocks = array
        } else {
            return false
        }
        for block in blocks {
            if let hookList = block["hooks"] as? [[String: Any]] {
                for hook in hookList where isRunwayHook(hook) {
                    if let expectedURL, let hookURL = hook["url"] as? String {
                        if hookURL == expectedURL { return true }
                    } else {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func isRunwayHook(_ hook: [String: Any]) -> Bool {
        guard let type = hook["type"] as? String else { return false }
        if type == "http", let url = hook["url"] as? String,
            url.hasPrefix(Self.hookURLPrefix) && url.hasSuffix(Self.hookURLSuffix)
        {
            if let headers = hook["headers"] as? [String: String],
                headers["X-Runway-Session-Id"] != nil
            {
                return true
            }
            return false
        }
        if type == "command", let cmd = hook["command"] as? String {
            return cmd.contains("hangar hook-handler")
        }
        return false
    }

    private func removeExistingHooks(from hooks: inout [String: Any], events: [(event: String, matcher: String?)]) {
        for config in events {
            guard let eventData = hooks[config.event] else { continue }
            if let cleaned = removeRunwayHooksFromEvent(eventData) {
                hooks[config.event] = cleaned
            } else {
                hooks.removeValue(forKey: config.event)
            }
        }
    }

    private func removeRunwayHooksFromEvent(_ eventData: Any) -> [[String: Any]]? {
        let blocks: [[String: Any]]
        if let single = eventData as? [String: Any] {
            blocks = [single]
        } else if let array = eventData as? [[String: Any]] {
            blocks = array
        } else {
            return nil
        }
        var cleaned: [[String: Any]] = []
        for var block in blocks {
            if var hookList = block["hooks"] as? [[String: Any]] {
                hookList.removeAll { isRunwayHook($0) }
                if hookList.isEmpty { continue }
                block["hooks"] = hookList
            }
            cleaned.append(block)
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func mergeHookEvent(existing: Any?, matcher: String?, hook: [String: Any]) -> [[String: Any]] {
        var block: [String: Any] = [:]
        if let matcher { block["matcher"] = matcher }

        if let existing {
            let blocks: [[String: Any]]
            if let single = existing as? [String: Any] {
                blocks = [single]
            } else if let array = existing as? [[String: Any]] {
                blocks = array
            } else {
                blocks = []
            }
            var found = false
            var result = blocks
            for i in result.indices {
                let blockMatcher = result[i]["matcher"] as? String
                if blockMatcher == matcher {
                    var hookList = (result[i]["hooks"] as? [[String: Any]]) ?? []
                    hookList.append(hook)
                    result[i]["hooks"] = hookList
                    found = true
                    break
                }
            }
            if !found {
                block["hooks"] = [hook]
                result.append(block)
            }
            return result
        } else {
            block["hooks"] = [hook]
            return [block]
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HookInjectorTests`
Expected: All pass (including existing tests which use the legacy convenience API)

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusDetection/HookInjector.swift Tests/StatusDetectionTests/HookInjectorTests.swift
git commit -m "feat: generalize HookInjector with data-driven HookInjectionConfig"
```

---

### Task 9: Database Migration and Persistence for `useHappy`

**Files:**
- Modify: `Sources/Persistence/Database.swift:236-238`
- Modify: `Sources/Persistence/Records.swift:7-79`
- Test: `Tests/PersistenceTests/DatabaseTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `Tests/PersistenceTests/DatabaseTests.swift`:

```swift
@Test func sessionUseHappyPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "happy-test", path: "/tmp", useHappy: true)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.useHappy == true)
}

@Test func sessionUseHappyDefaultsFalse() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "normal", path: "/tmp")
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.useHappy == false)
}

@Test func sessionToolGeminiPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "gemini-test", path: "/tmp", tool: .gemini)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.tool == .gemini)
}

@Test func sessionToolCodexPersistence() throws {
    let db = try Database(inMemory: true)
    let session = Session(title: "codex-test", path: "/tmp", tool: .codex)
    try db.saveSession(session)

    let fetched = try db.session(id: session.id)
    #expect(fetched?.tool == .codex)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DatabaseTests`
Expected: Compilation errors — `useHappy` not in SessionRecord

- [ ] **Step 3: Add migration v14**

In `Sources/Persistence/Database.swift`, after the `v13_session_templates` migration block and before `try migrator.migrate(dbQueue)`:

```swift
migrator.registerMigration("v14_session_use_happy") { db in
    try db.alter(table: "sessions") { t in
        t.add(column: "useHappy", .boolean).notNull().defaults(to: false)
    }
}
```

- [ ] **Step 4: Update SessionRecord**

In `Sources/Persistence/Records.swift`, add to `SessionRecord` properties (after `var lastAccessedAt: Date`):

```swift
var useHappy: Bool
```

In `init(_ session: Session)`, add after `self.lastAccessedAt = session.lastAccessedAt`:

```swift
self.useHappy = session.useHappy
```

In `toSession()`, add `useHappy: useHappy` to the Session init call (after `lastAccessedAt: lastAccessedAt`):

```swift
func toSession() -> Session {
    Session(
        id: id,
        title: title,
        projectID: projectID,
        path: path,
        tool: Self.decodeTool(tool),
        status: SessionStatus(rawValue: status) ?? .stopped,
        worktreeBranch: worktreeBranch,
        prNumber: prNumber,
        issueNumber: issueNumber,
        parentID: parentID,
        command: command,
        permissionMode: PermissionMode(rawValue: permissionMode) ?? .default,
        useHappy: useHappy,
        sortOrder: sortOrder,
        createdAt: createdAt,
        lastAccessedAt: lastAccessedAt
    )
}
```

Update `encodeTool`/`decodeTool`:

```swift
static func encodeTool(_ tool: Tool) -> String {
    switch tool {
    case .claude: "claude"
    case .gemini: "gemini"
    case .codex: "codex"
    case .shell: "shell"
    case .custom(let name): name
    }
}

static func decodeTool(_ raw: String) -> Tool {
    switch raw {
    case "claude": .claude
    case "gemini": .gemini
    case "codex": .codex
    case "shell": .shell
    default: .custom(raw)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter DatabaseTests`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Persistence/Database.swift Sources/Persistence/Records.swift Tests/PersistenceTests/DatabaseTests.swift
git commit -m "feat: migration v14 for useHappy column and Gemini/Codex tool encoding"
```

---

### Task 10: Update RunwayStore — Multi-Agent Hooks and Happy Wrapping

**Files:**
- Modify: `Sources/App/RunwayStore.swift`

- [ ] **Step 1: Update `startHookServer` to inject all agents**

In `Sources/App/RunwayStore.swift`, find `startHookServer()` (~line 762). Replace the single Claude injection:

```swift
// Before (line 792):
try hookInjector.inject(port: port, force: true)

// After:
for config in HookInjectionConfig.allBuiltIn {
    do {
        try hookInjector.inject(port: port, config: config, force: true)
    } catch {
        print("[Runway] Failed to inject hooks for \(config.agentID): \(error)")
    }
}
```

- [ ] **Step 2: Update `handleHookEvent` to map Gemini events**

In `handleHookEvent` (~line 834), expand the switch to handle new event types:

```swift
switch event.event {
case .sessionStart:
    updateSessionStatus(id: event.sessionID, status: .running)
case .sessionEnd:
    updateSessionStatus(id: event.sessionID, status: .stopped)
case .stop:
    updateSessionStatus(id: event.sessionID, status: .idle)
case .userPromptSubmit:
    updateSessionStatus(id: event.sessionID, status: .running)
case .permissionRequest:
    updateSessionStatus(id: event.sessionID, status: .waiting)
case .beforeAgent:
    updateSessionStatus(id: event.sessionID, status: .running)
case .afterAgent:
    updateSessionStatus(id: event.sessionID, status: .idle)
case .notification:
    break
}
```

- [ ] **Step 3: Update `startTmuxSession` for Happy wrapping and multi-agent permissions**

In `startTmuxSession` (~line 435-446), replace the command construction:

```swift
let profile = profileForSession(session)
let toolCommand: String?
if profile.id == "shell" {
    toolCommand = nil
} else {
    var parts: [String] = []
    if session.useHappy {
        parts.append("happy")
        parts.append(session.tool.command)
    } else {
        parts.append(profile.command)
    }
    parts.append(contentsOf: profile.arguments)
    if session.tool.supportsPermissionModes {
        parts.append(contentsOf: session.permissionMode.cliFlags(for: session.tool))
    }
    toolCommand = parts.joined(separator: " ")
}
```

- [ ] **Step 4: Update `handleNewSessionRequest` to pass `useHappy`**

In `handleNewSessionRequest` (~line 364-374), where the Session is created, ensure `useHappy` is passed from the request:

```swift
let session = Session(
    title: request.title,
    projectID: request.projectID,
    parentID: request.parentID,
    path: request.path,
    tool: request.tool,
    worktreeBranch: request.useWorktree ? request.branchName : nil,
    issueNumber: request.issueNumber,
    permissionMode: resolvedMode,
    useHappy: request.useHappy
)
```

- [ ] **Step 5: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: multi-agent hook injection and Happy wrapping in RunwayStore"
```

---

### Task 11: Update NewSessionDialog UI

**Files:**
- Modify: `Sources/Views/Shared/NewSessionDialog.swift`

- [ ] **Step 1: Add `useHappy` state variable**

In `NewSessionDialog`, add to the "Normal session state" section (after line 31):

```swift
@State private var useHappy: Bool = false
```

- [ ] **Step 2: Update `normalSessionFields` — permission and prompt visibility**

Replace the permission mode guard (line 210):

```swift
// Before:
if selectedTool == .claude {
    permissionPicker
}

// After:
if selectedTool.supportsPermissionModes {
    permissionPicker
}
```

Add Happy toggle after the permission picker and before the worktree toggle (before line 215):

```swift
if selectedTool.supportsHappy {
    Toggle("Launch with Happy", isOn: $useHappy)
    if useHappy {
        Text("Wraps session with Happy for mobile access")
            .font(.caption2)
            .foregroundColor(theme.chrome.textDim)
    }
}
```

Replace the initial prompt guard (line 231):

```swift
// Before:
if selectedTool == .claude {
    promptEditor
}

// After:
if selectedTool.supportsInitialPrompt {
    promptEditor
}
```

- [ ] **Step 3: Update `createNormalSession()` to pass `useHappy`**

In `createNormalSession()` (line 427), update the `NewSessionRequest` creation:

```swift
let request = NewSessionRequest(
    title: title,
    projectID: selectedProjectID,
    parentID: parentID,
    path: path,
    tool: selectedTool,
    useWorktree: useWorktree,
    branchName: useWorktree ? branchName : nil,
    permissionMode: selectedTool.supportsPermissionModes ? permissionMode : .default,
    useHappy: selectedTool.supportsHappy ? useHappy : false,
    initialPrompt: (selectedTool.supportsInitialPrompt && !initialPrompt.isEmpty) ? initialPrompt : nil
)
```

- [ ] **Step 4: Reset `useHappy` when switching to incompatible tool**

Add an `onChange` to reset `useHappy` when the selected profile changes. After the existing `onChange(of: title)` block:

```swift
.onChange(of: selectedProfileID) {
    if !selectedTool.supportsHappy {
        useHappy = false
    }
}
```

- [ ] **Step 5: Build and test**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/Shared/NewSessionDialog.swift
git commit -m "feat: Happy toggle and multi-agent permission/prompt visibility in NewSessionDialog"
```

---

### Task 12: Full Test Suite and Cleanup

**Files:**
- All test targets

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 2: Fix any failures**

If any existing tests broke (e.g., tests that check `PermissionMode.cliFlags` without the `for:` parameter), update them.

Common fixes:
- `session.permissionMode.cliFlags` → `session.permissionMode.cliFlags(for: session.tool)`
- `AgentProfile.builtIn.count == 2` → `AgentProfile.builtIn.count == 4`

- [ ] **Step 3: Run build check**

Run: `swift build`
Expected: Build succeeds with no warnings

- [ ] **Step 4: Commit any test fixes**

```bash
git add -A
git commit -m "fix: update existing tests for multi-agent support changes"
```

---

### Task 13: Format and Lint

- [ ] **Step 1: Run formatter and linter**

Run: `make fix`
Expected: Any formatting issues auto-fixed

- [ ] **Step 2: Verify clean**

Run: `make check`
Expected: Build + test + lint + format-check all pass

- [ ] **Step 3: Final commit if needed**

```bash
git add -A
git commit -m "style: format and lint fixes"
```
