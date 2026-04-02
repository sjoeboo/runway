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

// MARK: - Group

@Test func groupIDGeneration() {
    let group = Group(name: "Feature Work", projectID: "proj-1234")
    #expect(group.id.hasPrefix("grp-"))

    let id2 = Group.generateID()
    #expect(group.id != id2)
}

@Test func groupDefaults() {
    let group = Group(name: "Tasks", projectID: "proj-1")
    #expect(group.parentGroupID == nil)
    #expect(group.sortOrder == 0)
    #expect(group.isExpanded == true)
}

@Test func groupNestedHierarchy() {
    let parent = Group(name: "Parent", projectID: "proj-1")
    let child = Group(name: "Child", projectID: "proj-1", parentGroupID: parent.id)
    #expect(child.parentGroupID == parent.id)
}
