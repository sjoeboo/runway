import Foundation

/// Configuration for an AI coding agent backend.
/// Defines how to launch the agent and detect its status from terminal output.
public struct AgentProfile: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let command: String
    public let arguments: [String]
    /// Substring patterns indicating the agent is actively working.
    public let runningPatterns: [String]
    /// Substring patterns indicating the agent needs user input/approval.
    public let waitingPatterns: [String]
    /// Substring patterns indicating the agent is idle/ready for input.
    public let idlePatterns: [String]
    /// Patterns that must appear at the start of a line to indicate idle.
    public let lineStartIdlePatterns: [String]
    /// Single characters used as spinner indicators (e.g., braille dots).
    public let spinnerChars: [String]
    /// Whether this agent supports Runway's HTTP hook protocol.
    public let hookEnabled: Bool
    /// SF Symbol name for the agent's icon.
    public let icon: String

    public init(
        id: String,
        name: String,
        command: String,
        arguments: [String] = [],
        runningPatterns: [String] = [],
        waitingPatterns: [String] = [],
        idlePatterns: [String] = [],
        lineStartIdlePatterns: [String] = [],
        spinnerChars: [String] = [],
        hookEnabled: Bool = false,
        icon: String = "terminal.fill"
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.runningPatterns = runningPatterns
        self.waitingPatterns = waitingPatterns
        self.idlePatterns = idlePatterns
        self.lineStartIdlePatterns = lineStartIdlePatterns
        self.spinnerChars = spinnerChars
        self.hookEnabled = hookEnabled
        self.icon = icon
    }
}

// MARK: - Built-in Profiles

extension AgentProfile {
    /// Claude Code — full detection patterns, hook support enabled.
    public static let claude = AgentProfile(
        id: "claude",
        name: "Claude Code",
        command: "claude",
        arguments: [],
        runningPatterns: [
            "ctrl+c to interrupt",
            "esc to interrupt",
            "Ctrl+C to interrupt",
            "⎿",
            "Working...",
            "Analyzing",
            "Reading",
            "Searching",
            "Writing",
            "Editing",
        ],
        waitingPatterns: [
            "Yes, allow once",
            "Yes, always allow",
            "No, deny once",
            "No, and tell Claude",
            "approve?",
            "Approve?",
            "(Y/n)",
            "(y/N)",
            "Allow?",
            "Try again",
            "What would you like",
            "Do you want to",
        ],
        idlePatterns: [
            "❯ ",
            "How can I help",
            "What would you like to do",
            "Enter your prompt",
        ],
        lineStartIdlePatterns: ["> ", "$ "],
        spinnerChars: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
        hookEnabled: true,
        icon: "sparkle"
    )

    /// Shell — minimal detection, no hooks.
    public static let shell = AgentProfile(
        id: "shell",
        name: "Shell",
        command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        arguments: [],
        runningPatterns: [],
        waitingPatterns: [],
        idlePatterns: [],
        lineStartIdlePatterns: ["$ ", "% ", "# ", "❯ "],
        spinnerChars: [],
        hookEnabled: false,
        icon: "terminal"
    )

    /// All built-in profiles.
    public static let builtIn: [AgentProfile] = [.claude, .shell]

    /// Look up the default built-in profile for a Tool enum value.
    public static func defaultProfile(for tool: Tool) -> AgentProfile {
        switch tool {
        case .claude: return .claude
        case .shell: return .shell
        case .custom(let name):
            return AgentProfile(
                id: name, name: name, command: name,
                lineStartIdlePatterns: ["$ ", "% ", "# ", "❯ "],
                icon: "terminal.fill"
            )
        }
    }

    /// Load user-defined profiles from ~/.runway/agents/
    public static func loadUserProfiles() -> [AgentProfile] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".runway/agents")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
        else { return [] }

        return
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> AgentProfile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(AgentProfile.self, from: data)
            }
    }
}
