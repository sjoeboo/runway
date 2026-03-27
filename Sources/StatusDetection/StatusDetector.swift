import Foundation
import Models

/// Detects the status of AI coding sessions via terminal buffer content analysis.
///
/// Ports the battle-tested detection patterns from Hangar's detector.go —
/// 90+ Claude-specific prompt words, spinner characters, and permission dialog strings.
public struct StatusDetector: Sendable {

    public init() {}

    /// Detect session status from terminal buffer content.
    ///
    /// Reads the last N lines and checks for busy/waiting/idle indicators.
    /// Returns nil if no confident detection can be made.
    public func detect(content: String, tool: Tool) -> SessionStatus? {
        let lines = content.components(separatedBy: "\n")
        let lastLines = lines.suffix(10).joined(separator: "\n")
        let stripped = stripANSI(lastLines)

        switch tool {
        case .claude:
            return detectClaude(stripped)
        case .shell:
            return detectShell(stripped)
        case .custom:
            return detectGeneric(stripped)
        }
    }

    // MARK: - Claude Code Detection

    private func detectClaude(_ content: String) -> SessionStatus? {
        // Busy indicators (running, processing)
        if containsAny(content, patterns: busyPatterns) {
            return .running
        }

        // Spinner characters (braille spinners used by Claude)
        if containsSpinner(content) {
            return .running
        }

        // Permission / waiting indicators
        if containsAny(content, patterns: waitingPatterns) {
            return .waiting
        }

        // Idle indicators (prompt ready for input)
        if containsAny(content, patterns: idlePatterns) {
            return .idle
        }

        return nil
    }

    private func detectShell(_ content: String) -> SessionStatus? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("$") || trimmed.hasSuffix("%") || trimmed.hasSuffix("#") || trimmed.hasSuffix("❯") {
            return .idle
        }
        return .running
    }

    private func detectGeneric(_ content: String) -> SessionStatus? {
        detectShell(content)
    }

    // MARK: - Patterns (ported from detector.go)

    private let busyPatterns = [
        "ctrl+c to interrupt",
        "esc to interrupt",
        "Ctrl+C to interrupt",
        "tokens",
        "cost:",
        "⎿",
        "Working...",
    ]

    private let waitingPatterns = [
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
    ]

    private let idlePatterns = [
        "❯ ",
        "> ",
        "$ ",
        "How can I help",
        "What would you like to do",
        "Enter your prompt",
    ]

    /// Braille spinner characters used by Claude Code.
    private let spinnerChars: Set<Character> = [
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
    ]

    private func containsSpinner(_ content: String) -> Bool {
        let lastLine = content.components(separatedBy: "\n").last ?? ""
        return lastLine.contains(where: { spinnerChars.contains($0) })
    }

    private func containsAny(_ content: String, patterns: [String]) -> Bool {
        patterns.contains(where: { content.contains($0) })
    }

    // MARK: - ANSI Stripping

    /// Strip ANSI escape sequences from terminal output.
    /// Optimized O(n) implementation (ported from Hangar's fixed O(n) version).
    private func stripANSI(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var inEscape = false

        for char in input {
            if inEscape {
                if char.isLetter || char == "m" || char == "H" || char == "J" || char == "K" {
                    inEscape = false
                }
                continue
            }
            if char == "\u{1B}" {
                inEscape = true
                continue
            }
            result.append(char)
        }
        return result
    }
}
