import Foundation
import GitHubOperations
import Testing

@testable import Views

// MARK: - Initials extraction

@Test func initialsHyphenSplit() {
    #expect(AssigneeAvatar.initials(for: "alice-bailey") == "AB")
}

@Test func initialsNoHyphenUsesFirstTwo() {
    #expect(AssigneeAvatar.initials(for: "mnicholson") == "MN")
}

@Test func initialsShortName() {
    #expect(AssigneeAvatar.initials(for: "mn") == "MN")
}

@Test func initialsSingleChar() {
    #expect(AssigneeAvatar.initials(for: "a") == "A")
}

@Test func initialsEmpty() {
    #expect(AssigneeAvatar.initials(for: "") == "?")
}

@Test func initialsMultipleHyphens() {
    // Only the first two hyphen-separated parts matter
    #expect(AssigneeAvatar.initials(for: "a-b-c") == "AB")
}

// MARK: - Stable color index

@Test func colorIndexDeterministic() {
    let idxA = AssigneeAvatar.colorIndex(for: "alice", paletteCount: 8)
    let idxB = AssigneeAvatar.colorIndex(for: "alice", paletteCount: 8)
    #expect(idxA == idxB)
}

@Test func colorIndexWithinPalette() {
    let idx = AssigneeAvatar.colorIndex(for: "alice", paletteCount: 8)
    #expect(idx >= 0)
    #expect(idx < 8)
}

@Test func colorIndexDoesNotUseHashValue() {
    // Swift's .hashValue is randomized per-launch. Our hash must be stable.
    let input = "mnicholson"
    let expected = input.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & Int.max }
    #expect(AssigneeAvatar.colorIndex(for: input, paletteCount: 8) == expected % 8)
}

// MARK: - AssigneePicker filter

@Test func pickerFilterMatchesLogin() {
    let collabs = [
        Collaborator(login: "alice-bailey", name: "Alice B"),
        Collaborator(login: "bob-chen", name: "Bob C"),
    ]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "alice")
    #expect(filtered.count == 1)
    #expect(filtered.first?.login == "alice-bailey")
}

@Test func pickerFilterMatchesName() {
    let collabs = [
        Collaborator(login: "ab", name: "Alice B"),
        Collaborator(login: "bc", name: "Bob C"),
    ]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "bob")
    #expect(filtered.first?.login == "bc")
}

@Test func pickerFilterEmptyQueryReturnsAll() {
    let collabs = [
        Collaborator(login: "a1", name: nil),
        Collaborator(login: "b1", name: nil),
    ]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "")
    #expect(filtered.count == 2)
}

@Test func pickerFilterCaseInsensitive() {
    let collabs = [Collaborator(login: "Alice", name: "Alice")]
    let filtered = AssigneePickerView.filter(collaborators: collabs, query: "ALICE")
    #expect(filtered.count == 1)
}
