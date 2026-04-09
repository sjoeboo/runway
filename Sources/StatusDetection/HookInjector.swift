import Foundation

/// Injects Runway hook entries into an AI agent's settings file.
///
/// Uses a read-preserve-modify-write pattern to preserve all existing settings
/// and user hooks while adding Runway's HTTP hooks for lifecycle events.
/// Supports multiple agents via `HookInjectionConfig`. Ported from Hangar's `claude_hooks.go`.
public struct HookInjector: Sendable {
    /// The HTTP hook URL template.
    private static let hookURLTemplate = "http://127.0.0.1:%d/hooks"

    /// Prefix to match existing Runway/Hangar HTTP hooks.
    private static let hookURLPrefix = "http://127.0.0.1:"
    private static let hookURLSuffix = "/hooks"

    public init() {}

    // MARK: - Config-based API

    /// Inject HTTP hooks into an agent's settings using a `HookInjectionConfig`.
    ///
    /// - Parameters:
    ///   - port: The port the hook server is listening on (default: 47437)
    ///   - config: The agent hook injection configuration
    ///   - force: Re-inject even if hooks are already present at the given port
    /// - Returns: `true` if hooks were newly installed or upgraded
    @discardableResult
    public func inject(port: UInt16 = 47437, config: HookInjectionConfig, force: Bool = false) throws -> Bool {
        let settingsPath = "\(config.configDir)/\(config.settingsFile)"

        return try withSettingsLock(path: settingsPath) {
            try handlePreSteps(config.preSteps, configDir: config.configDir)
            return try _inject(port: port, settingsPath: settingsPath, configDir: config.configDir, config: config, force: force)
        }
    }

    /// Remove Runway hooks from an agent's settings using a `HookInjectionConfig`.
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

    /// Check if hooks are currently installed for the given config.
    public func isInstalled(config: HookInjectionConfig) -> Bool {
        let settingsPath = "\(config.configDir)/\(config.settingsFile)"

        guard let rawSettings = try? readSettings(at: settingsPath),
            let hooks = rawSettings["hooks"] as? [String: Any]
        else {
            return false
        }

        return httpHooksInstalled(in: hooks, url: nil, events: config.events)
    }

    // MARK: - Legacy Convenience API (backward compatible)

    /// Inject HTTP hooks into Claude Code settings.
    ///
    /// - Parameters:
    ///   - port: The port the hook server is listening on (default: 47437)
    ///   - configDir: Path to Claude Code config directory (default: ~/.claude)
    ///   - force: Re-inject even if hooks are already present at the given port
    /// - Returns: `true` if hooks were newly installed or upgraded
    @discardableResult
    public func inject(port: UInt16 = 47437, configDir: String? = nil, force: Bool = false) throws -> Bool {
        let claudeConfig =
            configDir.map { dir in
                HookInjectionConfig(
                    agentID: HookInjectionConfig.claude.agentID,
                    configDir: dir,
                    settingsFile: HookInjectionConfig.claude.settingsFile,
                    events: HookInjectionConfig.claude.events,
                    headerKey: HookInjectionConfig.claude.headerKey,
                    envVar: HookInjectionConfig.claude.envVar,
                    timeout: HookInjectionConfig.claude.timeout
                )
            } ?? HookInjectionConfig.claude
        return try inject(port: port, config: claudeConfig, force: force)
    }

    /// Remove Runway hooks from Claude Code settings.
    public func remove(configDir: String? = nil) throws {
        let claudeConfig =
            configDir.map { dir in
                HookInjectionConfig(
                    agentID: HookInjectionConfig.claude.agentID,
                    configDir: dir,
                    settingsFile: HookInjectionConfig.claude.settingsFile,
                    events: HookInjectionConfig.claude.events,
                    headerKey: HookInjectionConfig.claude.headerKey,
                    envVar: HookInjectionConfig.claude.envVar,
                    timeout: HookInjectionConfig.claude.timeout
                )
            } ?? HookInjectionConfig.claude
        try remove(config: claudeConfig)
    }

    /// Check if hooks are currently installed.
    public func isInstalled(configDir: String? = nil) -> Bool {
        let claudeConfig =
            configDir.map { dir in
                HookInjectionConfig(
                    agentID: HookInjectionConfig.claude.agentID,
                    configDir: dir,
                    settingsFile: HookInjectionConfig.claude.settingsFile,
                    events: HookInjectionConfig.claude.events,
                    headerKey: HookInjectionConfig.claude.headerKey,
                    envVar: HookInjectionConfig.claude.envVar,
                    timeout: HookInjectionConfig.claude.timeout
                )
            } ?? HookInjectionConfig.claude
        return isInstalled(config: claudeConfig)
    }

    // MARK: - Private Core Logic

    private func _inject(
        port: UInt16,
        settingsPath: String,
        configDir dir: String,
        config: HookInjectionConfig,
        force: Bool
    ) throws -> Bool {
        // Read existing settings (or start fresh)
        var rawSettings = try readSettings(at: settingsPath)

        // Parse existing hooks section
        var hooks = (rawSettings["hooks"] as? [String: Any]) ?? [:]

        // Check if HTTP hooks are already installed at this port (skip if force)
        let hookURL = String(format: Self.hookURLTemplate, Int(port))
        if !force && httpHooksInstalled(in: hooks, url: hookURL, events: config.events) {
            return false
        }

        // Remove any existing Runway/Hangar hooks (upgrade path)
        removeExistingHooks(from: &hooks, events: config.events)

        // Build the HTTP hook entry
        let hookEntry: [String: Any] = [
            "type": "http",
            "url": hookURL,
            "headers": [config.headerKey: "$\(config.envVar)"],
            "allowedEnvVars": [config.envVar],
            "timeout": config.timeout,
        ]

        // Inject our hook entries for each event
        for eventConfig in config.events {
            hooks[eventConfig.event] = mergeHookEvent(
                existing: hooks[eventConfig.event],
                matcher: eventConfig.matcher,
                hook: hookEntry
            )
        }

        // Write back
        rawSettings["hooks"] = hooks
        try writeSettings(rawSettings, to: settingsPath, configDir: dir)
        return true
    }

    // MARK: - Pre-injection Steps

    private func handlePreSteps(_ steps: [PreInjectionStep], configDir: String) throws {
        for step in steps {
            switch step {
            case .ensureTOMLFlag(let file, let section, let key, let value):
                try ensureTOMLFlag(
                    filePath: "\(configDir)/\(file)",
                    configDir: configDir,
                    section: section,
                    key: key,
                    value: value
                )
            }
        }
    }

    /// Ensure a key=value pair exists under a section in a TOML file.
    /// Creates the file and/or section if needed. Adds the key if missing; leaves it alone if present.
    private func ensureTOMLFlag(
        filePath: String,
        configDir: String,
        section: String,
        key: String,
        value: String
    ) throws {
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        var lines: [String]
        if FileManager.default.fileExists(atPath: filePath),
            let content = try? String(contentsOfFile: filePath, encoding: .utf8)
        {
            lines = content.components(separatedBy: "\n")
            // Remove trailing empty element from split
            if lines.last?.isEmpty == true { lines.removeLast() }
        } else {
            lines = []
        }

        let sectionHeader = "[\(section)]"
        let entry = "\(key) = \(value)"

        // Find the section
        var sectionIndex: Int? = nil
        for (i, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == sectionHeader {
            sectionIndex = i
            break
        }

        if let sectionIndex {
            // Section exists — scan forward to find if key already exists in it
            var keyFound = false
            var insertAt = sectionIndex + 1
            var i = sectionIndex + 1
            while i < lines.count {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                // Stop at next section header
                if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[#") {
                    insertAt = i
                    break
                }
                // Check if key is already set
                let keyPrefix = "\(key)"
                if trimmed.hasPrefix(keyPrefix) {
                    let rest = trimmed.dropFirst(keyPrefix.count).trimmingCharacters(in: .whitespaces)
                    if rest.hasPrefix("=") {
                        keyFound = true
                        break
                    }
                }
                insertAt = i + 1
                i += 1
            }

            if !keyFound {
                lines.insert(entry, at: insertAt)
            }
        } else {
            // Section doesn't exist — append it
            if !lines.isEmpty && lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append(sectionHeader)
            lines.append(entry)
        }

        let newContent = lines.joined(separator: "\n") + "\n"
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Settings I/O

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

        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Acquire an exclusive advisory lock on settings file for the duration of a closure.
    /// Prevents race conditions with agent processes or other Runway instances writing concurrently.
    private func withSettingsLock<T>(path: String, body: () throws -> T) throws -> T {
        let lockPath = path + ".lock"
        let lockFD = open(lockPath, O_CREAT | O_WRONLY, 0o644)
        guard lockFD >= 0 else {
            print("[Runway] Warning: could not create lock file at \(lockPath), proceeding without lock")
            return try body()
        }
        defer {
            flock(lockFD, LOCK_UN)
            close(lockFD)
        }
        if flock(lockFD, LOCK_EX) != 0 {
            print("[Runway] Warning: flock failed on \(lockPath) (errno \(errno)), proceeding without lock")
        }
        return try body()
    }

    private func httpHooksInstalled(
        in hooks: [String: Any],
        url: String?,
        events: [(event: String, matcher: String?)]
    ) -> Bool {
        // Check if all events have our HTTP hook at the expected URL
        for eventConfig in events {
            guard let eventData = hooks[eventConfig.event] else { return false }
            if !eventContainsRunwayHook(eventData, expectedURL: url) { return false }
        }
        return true
    }

    private func eventContainsRunwayHook(_ eventData: Any, expectedURL: String? = nil) -> Bool {
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
                for hook in hookList where isRunwayHook(hook) {
                    // If a specific URL is expected, verify the port matches
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
            // Only match hooks with Runway's header, not Hangar's
            if let headers = hook["headers"] as? [String: String],
                headers.keys.contains(where: { $0.hasPrefix("X-Runway-") })
            {
                return true
            }
            return false
        }
        // Also match legacy Hangar command hooks for cleanup
        if type == "command", let cmd = hook["command"] as? String {
            return cmd.contains("hangar hook-handler")
        }
        return false
    }

    private func removeExistingHooks(
        from hooks: inout [String: Any],
        events: [(event: String, matcher: String?)]
    ) {
        for eventConfig in events {
            guard let eventData = hooks[eventConfig.event] else { continue }
            if let cleaned = removeRunwayHooksFromEvent(eventData) {
                hooks[eventConfig.event] = cleaned
            } else {
                hooks.removeValue(forKey: eventConfig.event)
            }
        }
    }

    /// Remove Runway hooks from an event's matcher blocks. Returns nil if event should be removed entirely.
    /// Always returns [[String: Any]] to maintain array format required by agent config schemas.
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

    /// Merge our hook entry into an event's existing matcher blocks.
    /// Always returns [[String: Any]] — agent config schemas require the array format for all hook events.
    private func mergeHookEvent(existing: Any?, matcher: String?, hook: [String: Any]) -> [[String: Any]] {
        var block: [String: Any] = [:]
        if let matcher {
            block["matcher"] = matcher
        }

        if let existing {
            // Normalise to array (handle legacy object format written by older versions)
            let blocks: [[String: Any]]
            if let single = existing as? [String: Any] {
                blocks = [single]
            } else if let array = existing as? [[String: Any]] {
                blocks = array
            } else {
                blocks = []
            }

            // Find a block with matching matcher (or no matcher) and append our hook
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
