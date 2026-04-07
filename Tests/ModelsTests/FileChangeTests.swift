import Foundation
import Testing

@testable import Models

// MARK: - FileChange

@Test func fileChangeProperties() {
    let change = FileChange(path: "src/auth/middleware.ts", status: .modified, additions: 45, deletions: 12)
    #expect(change.id == "src/auth/middleware.ts")
    #expect(change.path == "src/auth/middleware.ts")
    #expect(change.status == .modified)
    #expect(change.additions == 45)
    #expect(change.deletions == 12)
}

@Test func fileChangeStatusCases() {
    #expect(FileChangeStatus.added != FileChangeStatus.deleted)
    #expect(FileChangeStatus.modified != FileChangeStatus.renamed)
    let all: [FileChangeStatus] = [.added, .modified, .deleted, .renamed]
    #expect(all.count == 4)
}

// MARK: - ChangesMode

@Test func changesModeHasExpectedCases() {
    let branch = ChangesMode.branch
    let working = ChangesMode.working
    #expect(branch != working)
}

// MARK: - FileTreeNode

@Test func fileTreeNodeFileID() {
    let change = FileChange(path: "README.md", status: .modified, additions: 1, deletions: 0)
    let node = FileTreeNode.file(change)
    #expect(node.id == "README.md")
    #expect(node.name == "README.md")
    #expect(node.additions == 1)
    #expect(node.deletions == 0)
}

@Test func fileTreeNodeDirectoryAggregates() {
    let child1 = FileChange(path: "src/a.ts", status: .modified, additions: 10, deletions: 5)
    let child2 = FileChange(path: "src/b.ts", status: .added, additions: 20, deletions: 0)
    let dir = FileTreeNode.directory(
        name: "src/",
        children: [.file(child1), .file(child2)],
        additions: 30,
        deletions: 5
    )
    #expect(dir.id == "dir:src/")
    #expect(dir.name == "src/")
    #expect(dir.additions == 30)
    #expect(dir.deletions == 5)
}

// MARK: - buildFileTree

@Test func buildFileTreeSingleRootFile() {
    let changes = [FileChange(path: "README.md", status: .modified, additions: 1, deletions: 0)]
    let tree = buildFileTree(changes)
    #expect(tree.count == 1)
    if case .file(let fc) = tree[0] {
        #expect(fc.path == "README.md")
    } else {
        Issue.record("Expected file node")
    }
}

@Test func buildFileTreeGroupsByDirectory() {
    let changes = [
        FileChange(path: "src/auth/middleware.ts", status: .modified, additions: 45, deletions: 12),
        FileChange(path: "src/auth/jwt.ts", status: .added, additions: 38, deletions: 0),
        FileChange(path: "package.json", status: .modified, additions: 2, deletions: 1),
    ]
    let tree = buildFileTree(changes)
    // Should have: dir "src/auth/" with 2 files, and file "package.json"
    #expect(tree.count == 2)

    // Find the directory node
    let dirNode = tree.first { $0.name == "src/auth/" }
    #expect(dirNode != nil)
    if case .directory(_, let children, let adds, let dels) = dirNode {
        #expect(children.count == 2)
        #expect(adds == 83)
        #expect(dels == 12)
    }
}

@Test func buildFileTreeCollapsesSingleChildDirs() {
    // src/deep/nested/file.ts should collapse src/deep/nested/ into one dir
    let changes = [
        FileChange(path: "src/deep/nested/file.ts", status: .added, additions: 10, deletions: 0)
    ]
    let tree = buildFileTree(changes)
    #expect(tree.count == 1)
    if case .directory(let name, let children, _, _) = tree[0] {
        #expect(name == "src/deep/nested/")
        #expect(children.count == 1)
    } else {
        Issue.record("Expected collapsed directory node")
    }
}

@Test func buildFileTreeSortsDirectoriesBeforeFiles() {
    let changes = [
        FileChange(path: "zz-root-file.txt", status: .modified, additions: 1, deletions: 0),
        FileChange(path: "src/file.ts", status: .added, additions: 5, deletions: 0),
    ]
    let tree = buildFileTree(changes)
    #expect(tree.count == 2)
    // Directory should come first
    if case .directory = tree[0] {
        // good
    } else {
        Issue.record("Expected directory first")
    }
}

@Test func buildFileTreeEmpty() {
    let tree = buildFileTree([])
    #expect(tree.isEmpty)
}
