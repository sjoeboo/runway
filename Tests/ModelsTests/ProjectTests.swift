import Foundation
import Testing

@testable import Models

// MARK: - Project

@Test func projectIDGeneration() {
    let project = Project(name: "Test", path: "/tmp")
    #expect(project.id.hasPrefix("proj-"))
    #expect(project.id.count > 5)

    let id2 = Project.generateID()
    #expect(project.id != id2)
}

@Test func projectDefaults() {
    let project = Project(name: "My App", path: "/code/myapp")
    #expect(project.name == "My App")
    #expect(project.path == "/code/myapp")
    #expect(project.defaultBranch == "main")
    #expect(project.sortOrder == 0)
}

@Test func projectCustomBranch() {
    let project = Project(name: "Legacy", path: "/code/legacy", defaultBranch: "master")
    #expect(project.defaultBranch == "master")
}
