import Foundation
import Testing

@testable import App

@Test func parseSessionURL() throws {
    let url = try #require(URL(string: "runway://session/id-abc123"))
    let result = DeepLinkRouter.parse(url)
    if case .session(let id) = result {
        #expect(id == "id-abc123")
    } else {
        Issue.record("Expected .session, got \(String(describing: result))")
    }
}

@Test func parsePRURL() throws {
    let url = try #require(URL(string: "runway://pr/42/owner/repo"))
    let result = DeepLinkRouter.parse(url)
    if case .pr(let number, let repo) = result {
        #expect(number == 42)
        #expect(repo == "owner/repo")
    } else {
        Issue.record("Expected .pr, got \(String(describing: result))")
    }
}

@Test func parseNewSessionURL() throws {
    let url = try #require(URL(string: "runway://new-session"))
    let result = DeepLinkRouter.parse(url)
    if case .newSession = result {
        // pass
    } else {
        Issue.record("Expected .newSession, got \(String(describing: result))")
    }
}

@Test func parseUnknownScheme() throws {
    let url = try #require(URL(string: "https://example.com"))
    #expect(DeepLinkRouter.parse(url) == nil)
}

@Test func parseUnknownHost() throws {
    let url = try #require(URL(string: "runway://unknown/path"))
    #expect(DeepLinkRouter.parse(url) == nil)
}

@Test func parseSessionURLMissingID() throws {
    let url = try #require(URL(string: "runway://session"))
    #expect(DeepLinkRouter.parse(url) == nil)
}

@Test func parsePRURLMissingNumber() throws {
    let url = try #require(URL(string: "runway://pr/notanumber/repo"))
    #expect(DeepLinkRouter.parse(url) == nil)
}
