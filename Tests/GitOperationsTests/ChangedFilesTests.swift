import Foundation
import Models
import Testing

@testable import GitOperations

// MARK: - Unit Tests: parseChangedFiles

@Test func parseChangedFilesTypicalOutput() {
    let numstat = """
        12\t3\tSources/App/Foo.swift
        0\t5\tSources/Models/Bar.swift
        7\t0\tSources/Views/Baz.swift
        -\t-\tSources/Theme/Old.swift
        """
    let nameStatus = """
        M\tSources/App/Foo.swift
        D\tSources/Models/Bar.swift
        A\tSources/Views/Baz.swift
        D\tSources/Theme/Old.swift
        """

    let changes = parseChangedFiles(numstat: numstat, nameStatus: nameStatus)
    #expect(changes.count == 4)

    let foo = changes.first { $0.path == "Sources/App/Foo.swift" }
    #expect(foo?.status == .modified)
    #expect(foo?.additions == 12)
    #expect(foo?.deletions == 3)

    let bar = changes.first { $0.path == "Sources/Models/Bar.swift" }
    #expect(bar?.status == .deleted)
    #expect(bar?.additions == 0)
    #expect(bar?.deletions == 5)

    let baz = changes.first { $0.path == "Sources/Views/Baz.swift" }
    #expect(baz?.status == .added)
    #expect(baz?.additions == 7)
    #expect(baz?.deletions == 0)

    let old = changes.first { $0.path == "Sources/Theme/Old.swift" }
    #expect(old?.status == .deleted)
    // Binary files show "-" which parses as 0
    #expect(old?.additions == 0)
    #expect(old?.deletions == 0)
}

@Test func parseChangedFilesEmptyOutput() {
    let changes = parseChangedFiles(numstat: "", nameStatus: "")
    #expect(changes.isEmpty)
}

@Test func parseChangedFilesRenamedFile() {
    // R100 status + "old => new" in numstat
    let numstat = """
        3\t1\tSources/{Old => New}/File.swift
        """
    let nameStatus = """
        R100\tSources/Old/File.swift\tSources/New/File.swift
        """

    let changes = parseChangedFiles(numstat: numstat, nameStatus: nameStatus)
    #expect(changes.count == 1)
    let change = try? #require(changes.first)
    #expect(change?.status == .renamed)
    // The path should be the new path from name-status
    #expect(change?.path == "Sources/New/File.swift")
    #expect(change?.additions == 3)
    #expect(change?.deletions == 1)
}

// MARK: - Integration Tests (temp git repo)

/// Creates a temporary git repository for testing.
/// Resolves symlinks to avoid /var vs /private/var mismatches on macOS.
private func withTempGitRepo(_ body: (String) async throws -> Void) async throws {
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("runway-git-test-\(UUID().uuidString)")
        .resolvingSymlinksInPath()
    let tmpDir = tmpURL.path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

    // Initialize a git repo with an initial commit
    let commands = [
        "git init",
        "git config user.email 'test@test.com'",
        "git config user.name 'Test'",
        "echo 'hello' > README.md",
        "git add README.md",
        "git commit -m 'Initial commit'",
    ]
    for cmd in commands {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]
        process.currentDirectoryURL = URL(fileURLWithPath: tmpDir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    try await body(tmpDir)
}

/// Run a shell command in a directory, ignoring output.
private func sh(_ cmd: String, in dir: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", cmd]
    process.currentDirectoryURL = URL(fileURLWithPath: dir)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
}

@Test func changedFilesOnCleanRepo() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()
        let changes = await manager.changedFiles(path: repoPath, mode: .working)
        #expect(changes.isEmpty)
    }
}

@Test func changedFilesDetectsNewFile() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()

        // Create and stage a new file
        try sh("echo 'new content' > NewFile.swift && git add NewFile.swift", in: repoPath)

        let changes = await manager.changedFiles(path: repoPath, mode: .working)
        #expect(!changes.isEmpty)

        let newFile = changes.first { $0.path == "NewFile.swift" }
        #expect(newFile != nil)
        #expect(newFile?.status == .added)
    }
}

@Test func fileDiffReturnsUnifiedDiff() async throws {
    try await withTempGitRepo { repoPath in
        let manager = WorktreeManager()

        // Modify and stage README.md
        try sh("echo 'modified content' > README.md && git add README.md", in: repoPath)

        let diff = await manager.fileDiff(path: repoPath, file: "README.md", mode: .working)
        let diffText = try #require(diff)
        #expect(diffText.contains("@@"))
        #expect(!diffText.isEmpty)
    }
}
