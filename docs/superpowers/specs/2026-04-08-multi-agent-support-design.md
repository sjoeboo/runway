# Multi-Agent Support Design

## Summary

Add first-class support for Gemini CLI and Codex alongside Claude Code, with a Happy wrapper toggle for mobile/remote session access. All three agents get built-in profiles with terminal pattern detection, lifecycle hook injection, and permission mode mapping. Happy wraps any compatible agent at launch time via a checkbox in the New Session dialog.

## Problem

Runway currently only supports Claude Code as a first-class agent. The `Tool` enum has `.claude`, `.shell`, and `.custom(String)`, with status detection patterns, hook injection, and permission modes all hardcoded for Claude. Users who want to use Gemini CLI or Codex must create manual JSON profiles in `~/.runway/agents/` and lose hook-based real-time status detection, permission mode mapping, and a polished UI experience.

## Agents

### Gemini CLI (Google)
- **Command:** `gemini`
- **Install:** `npm install -g @google/gemini-cli`
- **TUI:** Ink (React for terminals)
- **Hooks:** 11 events in `~/.gemini/settings.json`, same JSON structure as Claude
- **Config:** `~/.gemini/settings.json`

### Codex (OpenAI)
- **Command:** `codex`
- **Install:** `npm install -g @openai/codex`
- **TUI:** Ratatui (Rust, full-screen alternate buffer)
- **Hooks:** 5 events in `~/.codex/hooks.json`, requires `codex_hooks = true` in `~/.codex/config.toml`
- **Config:** `~/.codex/config.toml` + `~/.codex/hooks.json`

### Happy (Wrapper)
- **Command:** `happy <agent>` (e.g., `happy claude`, `happy gemini`, `happy codex`)
- **Install:** `npm install -g happy`
- **Purpose:** Wraps any agent with mobile/remote access via QR code pairing, push notifications, and E2E encrypted relay
- **Transparent:** The underlying agent still writes its own hooks and produces the same terminal output

## Architecture: Data-Driven Hook Injection

A single generalized `HookInjector` accepts a `HookInjectionConfig` struct per agent, replacing the current Claude-hardcoded implementation.

## Models

### Tool Enum

Add `.gemini` and `.codex` as first-class cases:

```swift
public enum Tool: Codable, Sendable, Hashable {
    case claude
    case gemini
    case codex
    case shell
    case custom(String)
}
```

Properties:
- `.gemini` → `command: "gemini"`, `displayName: "Gemini CLI"`
- `.codex` → `command: "codex"`, `displayName: "Codex"`

Convenience computed properties on `Tool`:
- `supportsPermissionModes` — `true` for `.claude`, `.gemini`, `.codex`
- `supportsInitialPrompt` — `true` for `.claude`, `.gemini`, `.codex`
- `supportsHappy` — `true` for `.claude`, `.gemini`, `.codex`
- `isAgent` — `true` for everything except `.shell`

### Codable

`SessionRecord.encodeTool`/`decodeTool` gains `"gemini"` and `"codex"` cases. Existing databases with unknown tool strings already fall through to `.custom(raw)`, so no data loss.

### Session — `useHappy: Bool`

New field on `Session`, default `false`. When `true`, the launch command wraps the agent: `happy claude` instead of `claude`. Persisted so restarts re-wrap correctly.

### NewSessionRequest — `useHappy: Bool`

Same field, passed from the dialog.

### PermissionMode — Agent-Specific Flags

Replace `cliFlags` computed property with a method:

```swift
public func cliFlags(for tool: Tool) -> [String] {
    switch (self, tool) {
    case (.default, _):            []
    case (.acceptEdits, .claude):  ["--accept-edits"]
    case (.acceptEdits, .gemini):  ["--yolo"]
    case (.acceptEdits, .codex):   ["--full-auto"]
    case (.bypassAll, .claude):    ["--dangerously-skip-permissions"]
    case (.bypassAll, .gemini):    ["--yolo"]
    case (.bypassAll, .codex):     ["--yolo"]
    default:                       []
    }
}
```

Note: Gemini's `--yolo` maps to both Accept Edits and Bypass All because it has no intermediate mode. This is the best-effort mapping — the dialog labels remain Runway's generic terminology.

### AgentProfile — Built-in Profiles

#### Gemini CLI
```swift
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
```

#### Codex
```swift
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

Codex includes `--no-alt-screen` in default arguments because its Ratatui TUI uses the alternate screen buffer, which hides output from tmux buffer reads. This flag preserves scrollback for buffer-based status detection.

Update `builtIn` array and `defaultProfile(for:)` to include both new profiles.

## Hook Injection

### HookInjectionConfig

New struct in StatusDetection:

```swift
public struct HookInjectionConfig: Sendable {
    let agentID: String
    let configDir: String
    let settingsFile: String
    let events: [(event: String, matcher: String?)]
    let headerKey: String
    let envVar: String
    let timeout: Int
    let preSteps: [PreInjectionStep]
}

public enum PreInjectionStep: Sendable {
    case ensureTOMLFlag(file: String, section: String, key: String, value: String)
}
```

### Per-Agent Configs

**Claude:**
- `configDir: ~/.claude`, `settingsFile: settings.json`
- Events: SessionStart, UserPromptSubmit, Stop, PermissionRequest, Notification (matcher: `permission_prompt|elicitation_dialog`), SessionEnd
- No pre-steps

**Gemini CLI:**
- `configDir: ~/.gemini`, `settingsFile: settings.json`
- Events: SessionStart, SessionEnd, BeforeAgent, AfterAgent, Notification
- No pre-steps
- Same JSON hook format as Claude (Gemini adopted Claude's structure)

**Codex:**
- `configDir: ~/.codex`, `settingsFile: hooks.json`
- Events: SessionStart, UserPromptSubmit, Stop
- Pre-step: `ensureTOMLFlag(file: "config.toml", section: "features", key: "codex_hooks", value: "true")`

### Generalized HookInjector

Refactor `HookInjector` to accept `HookInjectionConfig`:
- `inject(port:config:force:)` replaces `inject(port:configDir:force:)`
- Read/write/lock/merge logic is reused — already generic JSON manipulation
- New `handlePreSteps(_ steps:config:)` processes `PreInjectionStep` cases
- The `remove(config:)` method cleans up per-agent

### Startup Injection

`RunwayStore.startHookServer()` injects hooks for all built-in agents at launch:

```swift
for config in HookInjectionConfig.allBuiltIn {
    try hookInjector.inject(port: port, config: config, force: true)
}
```

## Status Detection

### Buffer Detection

No changes to `StatusDetector`. It's already profile-driven — the new `AgentProfile` patterns handle Gemini and Codex detection automatically.

### Hook Event Mapping

Existing `handleHookEvent` status mapping works for Claude. For Gemini and Codex, the event vocabulary differs:

| Runway Status | Claude | Gemini | Codex |
|---|---|---|---|
| `.running` | SessionStart | SessionStart | SessionStart |
| `.running` | UserPromptSubmit | BeforeAgent | UserPromptSubmit |
| `.idle` | Stop | AfterAgent | Stop |
| `.stopped` | SessionEnd | SessionEnd | *(none)* |
| `.waiting` | PermissionRequest | *(buffer only)* | *(buffer only)* |

Gemini and Codex lack a dedicated permission-request hook event. Their `.waiting` detection relies on buffer polling, which matches distinctive permission dialog text ("Action Required", "Would you like to run"). Hooks handle the high-frequency `.running`/`.idle` transitions; buffer polling handles the nuanced `.waiting` detection.

The `handleHookEvent` method needs a lookup from agent-specific event names to Runway statuses. Add a mapping table:

```swift
private static let eventStatusMap: [String: SessionStatus] = [
    // Claude
    "SessionStart": .running,
    "UserPromptSubmit": .running,
    "Stop": .idle,
    "PermissionRequest": .waiting,
    "SessionEnd": .stopped,
    // Gemini (additional)
    "BeforeAgent": .running,
    "AfterAgent": .idle,
    // Codex uses same names as Claude — no additions needed
]
```

`Notification` events (from any agent) are logged but don't change status.

### Hook Priority Cooldown

Unchanged — 10-second cooldown after hook events before buffer polling resumes. This allows buffer polling to detect `.waiting` transitions that hooks don't report.

## UI Changes

### NewSessionDialog

**Agent picker:** Already iterates `profiles` array — adding to `AgentProfile.builtIn` is sufficient.

**Permission picker visibility:** Expand from `selectedTool == .claude` to `selectedTool.supportsPermissionModes`.

**Initial prompt visibility:** Expand from `selectedTool == .claude` to `selectedTool.supportsInitialPrompt`.

**Happy toggle:** New checkbox between permission picker and worktree toggle:
```swift
if selectedTool.supportsHappy {
    Toggle("Launch with Happy", isOn: $useHappy)
}
```
Shows a caption "Wraps session with Happy for mobile access" when enabled.

**`createNormalSession()`:** Pass `useHappy` to `NewSessionRequest`. Update permission mode guard.

### Sidebar Icons

SF Symbol per agent: Claude `sparkle`, Gemini `diamond.fill`, Codex `cpu`, Shell `terminal`.

## Terminal Launch

### Command Construction

In `RunwayStore.startTmuxSession`:

```swift
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
```

Happy passes unknown flags through to the underlying agent, so permission flags work transparently.

### Codex Alternate Screen

Codex profile includes `--no-alt-screen` in default arguments to prevent Ratatui from hiding output in the alternate screen buffer. Without this, buffer-based status detection would fail for Codex sessions.

## Database

### Migration v14

```swift
migrator.registerMigration("v14_session_use_happy") { db in
    try db.alter(table: "sessions") { t in
        t.add(column: "useHappy", .boolean).notNull().defaults(to: false)
    }
}
```

### SessionRecord

Add `var useHappy: Bool`. Wire through `init(session:)` and `toSession()`.

### No Template Changes

`SessionTemplate` does not gain a `useHappy` field. Happy is a per-session launch preference, not a reusable template property.

## Files Changed

| Area | File | Changes |
|---|---|---|
| Models | `Session.swift` | Add `.gemini`, `.codex` to Tool; add `useHappy`; add Tool convenience properties; refactor `PermissionMode.cliFlags(for:)` |
| Models | `AgentProfile.swift` | Add `.gemini`, `.codex` built-in profiles; update `builtIn` and `defaultProfile(for:)` |
| Models | `NewSessionRequest.swift` | Add `useHappy: Bool` |
| StatusDetection | `HookInjector.swift` | Generalize to accept `HookInjectionConfig`; add TOML pre-step support |
| StatusDetection | **New:** `HookInjectionConfig.swift` | Config struct + built-in configs for all three agents |
| App | `RunwayStore.swift` | Inject hooks for all agents at startup; Happy wrapping in `startTmuxSession`; expand permission mode guard |
| Views | `NewSessionDialog.swift` | Happy toggle; expand permission/prompt visibility |
| Persistence | `Database.swift` | Migration v14 |
| Persistence | `Records.swift` | Encode/decode `.gemini`, `.codex`, `useHappy` |

## Testing

- **ModelsTests:** Tool encoding/decoding round-trips for `.gemini`, `.codex`; `PermissionMode.cliFlags(for:)` mapping; `Tool` convenience properties
- **StatusDetectionTests:** Buffer detection with Gemini and Codex profiles; `HookInjectionConfig` validation; generalized `HookInjector` inject/remove for each agent
- **PersistenceTests:** Migration v14 adds `useHappy` column; session round-trip with `useHappy: true`
- **ViewsTests:** NewSessionDialog renders Happy toggle for agent tools, hides for shell
