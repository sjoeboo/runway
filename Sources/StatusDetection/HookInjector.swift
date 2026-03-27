import Foundation

/// Injects Runway hook entries into Claude Code's `~/.claude/settings.json`.
///
/// Uses a read-preserve-modify-write pattern to preserve all existing settings
/// and user hooks while adding Runway's HTTP hooks for lifecycle events.
/// Ported from Hangar's `claude_hooks.go`.
public struct HookInjector: Sendable {
    /// The HTTP hook URL template.
    private static let hookURLTemplate = "http://127.0.0.1:%d/hooks"

    /// Prefix to match existing Runway/Hangar HTTP hooks.
    private static let hookURLPrefix = "http://127.0.0.1:"
    private static let hookURLSuffix = "/hooks"

    /// Events we subscribe to and their optional matcher patterns.
    private static let hookEvents: [(event: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("UserPromptSubmit", nil),
        ("Stop", nil),
        ("PermissionRequest", nil),
        ("Notification", "permission_prompt|elicitation_dialog"),
        ("SessionEnd", nil),
    ]

    public init() {}

    /// Inject HTTP hooks into Claude Code settings.
    ///
    /// - Parameters:
    ///   - port: The port the hook server is listening on (default: 47437)
    ///   - configDir: Path to Claude Code config directory (default: ~/.claude)
    /// - Returns: `true` if hooks were newly installed or upgraded
    @discardableResult
    public func inject(port: UInt16 = 47437, configDir: String? = nil) throws -> Bool {
        let dir = configDir ?? defaultClaudeConfigDir()
        let settingsPath = "\(dir)/settings.json"

        // Read existing settings (or start fresh)
        var rawSettings = try readSettings(at: settingsPath)

        // Parse existing hooks section
        var hooks = (rawSettings["hooks"] as? [String: Any]) ?? [:]

        // Check if HTTP hooks are already installed at this port
        let hookURL = String(format: Self.hookURLTemplate, Int(port))
        if httpHooksInstalled(in: hooks, url: hookURL) {
            return false
        }

        // Remove any existing Runway/Hangar hooks (upgrade path)
        removeExistingHooks(from: &hooks)

        // Build the HTTP hook entry
        let hookEntry: [String: Any] = [
            "type": "http",
            "url": hookURL,
            "headers": ["X-Runway-Session-Id": "$RUNWAY_SESSION_ID"],
            "timeout": 5,
        ]

        // Inject our hook entries for each event
        for config in Self.hookEvents {
            hooks[config.event] = mergeHookEvent(
                existing: hooks[config.event],
                matcher: config.matcher,
                hook: hookEntry
            )
        }

        // Write back
        rawSettings["hooks"] = hooks
        try writeSettings(rawSettings, to: settingsPath, configDir: dir)
        return true
    }

    /// Remove Runway hooks from Claude Code settings.
    public func remove(configDir: String? = nil) throws {
        let dir = configDir ?? defaultClaudeConfigDir()
        let settingsPath = "\(dir)/settings.json"

        var rawSettings = try readSettings(at: settingsPath)
        guard var hooks = rawSettings["hooks"] as? [String: Any] else { return }

        removeExistingHooks(from: &hooks)

        if hooks.isEmpty {
            rawSettings.removeValue(forKey: "hooks")
        } else {
            rawSettings["hooks"] = hooks
        }

        try writeSettings(rawSettings, to: settingsPath, configDir: dir)
    }

    /// Check if hooks are currently installed.
    public func isInstalled(configDir: String? = nil) -> Bool {
        let dir = configDir ?? defaultClaudeConfigDir()
        let settingsPath = "\(dir)/settings.json"

        guard let rawSettings = try? readSettings(at: settingsPath),
              let hooks = rawSettings["hooks"] as? [String: Any] else {
            return false
        }

        return httpHooksInstalled(in: hooks, url: nil)
    }

    // MARK: - Private

    private func defaultClaudeConfigDir() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude"
    }

    private func readSettings(at path: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path) else {
            return [:]
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func writeSettings(_ settings: [String: Any], to path: String, configDir: String) throws {
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )

        // Atomic write: tmpfile + rename
        let tmpPath = path + ".tmp"
        try data.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)
        try FileManager.default.moveItem(atPath: tmpPath, toPath: path)
    }

    private func httpHooksInstalled(in hooks: [String: Any], url: String?) -> Bool {
        // Check if at least one event has our HTTP hook
        for config in Self.hookEvents {
            guard let eventData = hooks[config.event] else { return false }
            if !eventContainsRunwayHook(eventData) { return false }
        }
        return true
    }

    private func eventContainsRunwayHook(_ eventData: Any) -> Bool {
        // Event can be a single matcher block or array of matcher blocks
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
                for hook in hookList {
                    if isRunwayHook(hook) { return true }
                }
            }
        }
        return false
    }

    private func isRunwayHook(_ hook: [String: Any]) -> Bool {
        guard let type = hook["type"] as? String else { return false }
        if type == "http", let url = hook["url"] as? String {
            return url.hasPrefix(Self.hookURLPrefix) && url.hasSuffix(Self.hookURLSuffix)
        }
        // Also match legacy Hangar command hooks for cleanup
        if type == "command", let cmd = hook["command"] as? String {
            return cmd.contains("hangar hook-handler")
        }
        return false
    }

    private func removeExistingHooks(from hooks: inout [String: Any]) {
        for config in Self.hookEvents {
            guard let eventData = hooks[config.event] else { continue }
            if let cleaned = removeRunwayHooksFromEvent(eventData) {
                hooks[config.event] = cleaned
            } else {
                hooks.removeValue(forKey: config.event)
            }
        }
    }

    /// Remove Runway hooks from an event's matcher blocks. Returns nil if event should be removed entirely.
    private func removeRunwayHooksFromEvent(_ eventData: Any) -> Any? {
        let blocks: [[String: Any]]
        if let single = eventData as? [String: Any] {
            blocks = [single]
        } else if let array = eventData as? [[String: Any]] {
            blocks = array
        } else {
            return eventData
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

        if cleaned.isEmpty { return nil }
        return cleaned.count == 1 ? cleaned[0] : cleaned
    }

    /// Merge our hook entry into an event's existing matcher blocks.
    private func mergeHookEvent(existing: Any?, matcher: String?, hook: [String: Any]) -> Any {
        var block: [String: Any] = [:]
        if let matcher {
            block["matcher"] = matcher
        }

        if let existing {
            // Append to existing blocks
            let blocks: [[String: Any]]
            if let single = existing as? [String: Any] {
                blocks = [single]
            } else if let array = existing as? [[String: Any]] {
                blocks = array
            } else {
                blocks = []
            }

            // Find a block with matching matcher (or no matcher)
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

            return result.count == 1 ? result[0] : result
        } else {
            block["hooks"] = [hook]
            return block
        }
    }
}
