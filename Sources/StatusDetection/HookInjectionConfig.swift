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
            .ensureTOMLFlag(file: "config.toml", section: "features", key: "codex_hooks", value: "true")
        ]
    )

    /// All built-in hook injection configs.
    public static let allBuiltIn: [HookInjectionConfig] = [.claude, .gemini, .codex]
}
