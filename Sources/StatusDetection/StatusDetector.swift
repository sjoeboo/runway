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
        let profile = AgentProfile.defaultProfile(for: tool)
        return detect(content: content, profile: profile)
    }

    /// Detect session status using an agent profile's patterns.
    public func detect(content: String, profile: AgentProfile) -> SessionStatus? {
        let lines = content.components(separatedBy: "\n")
        let lastLines = lines.suffix(10).joined(separator: "\n")
        let stripped = stripANSI(lastLines)

        // Running: busy patterns or spinner
        if containsAny(stripped, patterns: profile.runningPatterns) {
            return .running
        }
        if !profile.spinnerChars.isEmpty {
            let spinnerSet = Set(profile.spinnerChars.compactMap(\.first))
            if containsSpinner(stripped, chars: spinnerSet) {
                return .running
            }
        }

        // Waiting
        if containsAny(stripped, patterns: profile.waitingPatterns) {
            return .waiting
        }

        // Idle
        if containsAny(stripped, patterns: profile.idlePatterns) {
            return .idle
        }
        if containsLineStartPattern(stripped, patterns: profile.lineStartIdlePatterns) {
            return .idle
        }

        // Fallback: profiles with no running/spinner patterns (like Shell)
        // If none of the above matched, and the profile has no way to detect "running",
        // default to .running (since we already checked idle patterns above)
        if profile.runningPatterns.isEmpty && profile.spinnerChars.isEmpty {
            return .running
        }

        return nil
    }

    private func containsSpinner(_ content: String, chars: Set<Character>) -> Bool {
        let lastLine = content.components(separatedBy: "\n").last ?? ""
        return lastLine.contains(where: { chars.contains($0) })
    }

    private func containsAny(_ content: String, patterns: [String]) -> Bool {
        patterns.contains(where: { content.contains($0) })
    }

    private func containsLineStartPattern(_ content: String, patterns: [String]) -> Bool {
        let lines = content.components(separatedBy: "\n")
        return lines.contains { line in
            patterns.contains { line.hasPrefix($0) }
        }
    }

    // MARK: - ANSI Stripping

    /// Strip ANSI escape sequences from terminal output.
    /// Handles CSI sequences (ESC[...letter), OSC sequences (ESC]...BEL/ST),
    /// and other escape types. O(n) state machine.
    private func stripANSI(_ input: String) -> String {
        enum State { case normal, escSeen, inCSI, inOSC }
        var result = ""
        result.reserveCapacity(input.count)
        var state = State.normal

        for char in input {
            switch state {
            case .normal:
                if char == "\u{1B}" {
                    state = .escSeen
                } else if char == "\u{07}" {
                    // Stray BEL — skip
                } else {
                    result.append(char)
                }
            case .escSeen:
                // Character immediately after ESC determines sequence type
                if char == "[" {
                    state = .inCSI
                } else if char == "]" {
                    state = .inOSC
                } else if char == "\\" {
                    // String Terminator (ESC \) — terminates OSC/DCS/etc.
                    state = .normal
                } else if char.isLetter {
                    // Two-character escape (e.g., ESC M) — done
                    state = .normal
                } else {
                    // Other escape introducer — treat as CSI-like
                    state = .inCSI
                }
            case .inCSI:
                // CSI final bytes are 0x40-0x7E per ECMA-48
                if let scalar = char.unicodeScalars.first,
                    scalar.value >= 0x40, scalar.value <= 0x7E
                {
                    state = .normal
                }
            case .inOSC:
                // OSC terminates on BEL or ST (ESC \)
                if char == "\u{07}" {
                    state = .normal
                } else if char == "\u{1B}" {
                    // Could be start of ST (ESC \) — peek handled: next char
                    // will be '\' which terminates, or another escape starts
                    state = .escSeen
                }
            }
        }
        return result
    }
}
