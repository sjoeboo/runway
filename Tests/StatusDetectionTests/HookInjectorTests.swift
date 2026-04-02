import Testing
import Foundation
@testable import StatusDetection

// MARK: - HookInjector Filesystem Tests

@Test func hookInjectorInjectCreatesSettings() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let injector = HookInjector()
    let installed = try injector.inject(port: 47437, configDir: tmpDir)
    #expect(installed == true)

    // Verify settings file was created
    let settingsPath = "\(tmpDir)/settings.json"
    #expect(FileManager.default.fileExists(atPath: settingsPath))

    // Verify JSON structure
    let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let hooks = json["hooks"] as! [String: Any]

    // Check that all expected events are present
    #expect(hooks["SessionStart"] != nil)
    #expect(hooks["UserPromptSubmit"] != nil)
    #expect(hooks["Stop"] != nil)
    #expect(hooks["PermissionRequest"] != nil)
    #expect(hooks["Notification"] != nil)
    #expect(hooks["SessionEnd"] != nil)
}

@Test func hookInjectorIdempotent() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let injector = HookInjector()
    let first = try injector.inject(port: 47437, configDir: tmpDir)
    #expect(first == true)

    let second = try injector.inject(port: 47437, configDir: tmpDir)
    #expect(second == false) // Already installed, no change
}

@Test func hookInjectorIsInstalled() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let injector = HookInjector()
    #expect(injector.isInstalled(configDir: tmpDir) == false)

    try injector.inject(port: 47437, configDir: tmpDir)
    #expect(injector.isInstalled(configDir: tmpDir) == true)
}

@Test func hookInjectorRemove() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let injector = HookInjector()
    try injector.inject(port: 47437, configDir: tmpDir)
    #expect(injector.isInstalled(configDir: tmpDir) == true)

    try injector.remove(configDir: tmpDir)
    #expect(injector.isInstalled(configDir: tmpDir) == false)
}

@Test func hookInjectorPreservesExistingSettings() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    // Create existing settings with custom data
    try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    let existing: [String: Any] = [
        "apiKey": "test-key",
        "model": "claude-4",
    ]
    let data = try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted)
    try data.write(to: URL(fileURLWithPath: "\(tmpDir)/settings.json"))

    let injector = HookInjector()
    try injector.inject(port: 47437, configDir: tmpDir)

    // Verify existing settings are preserved
    let updated = try Data(contentsOf: URL(fileURLWithPath: "\(tmpDir)/settings.json"))
    let json = try JSONSerialization.jsonObject(with: updated) as! [String: Any]
    #expect(json["apiKey"] as? String == "test-key")
    #expect(json["model"] as? String == "claude-4")
    #expect(json["hooks"] != nil)
}

@Test func hookInjectorRemoveFromEmptyDir() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("runway-test-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    let injector = HookInjector()
    // Should not throw when settings don't exist
    try injector.remove(configDir: tmpDir)
}
