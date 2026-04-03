import Foundation
import Testing

@testable import StatusDetection

@Test func hookServerStartsAndExposesPort() async throws {
    let server = HookServer(port: 0)
    try await server.start()
    defer { Task { await server.stop() } }

    let portValue = try #require(await server.actualPort)
    #expect(portValue > 0)
}

@Test func hookServerAcceptsConnections() async throws {
    let server = HookServer(port: 0)
    try await server.start()
    defer { Task { await server.stop() } }

    let portValue = try #require(await server.actualPort)

    // Send a minimal HTTP POST to the server
    let url = try #require(URL(string: "http://127.0.0.1:\(portValue)/hooks"))
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("test-session-123", forHTTPHeaderField: "X-Runway-Session-Id")

    let body: [String: Any] = [
        "sessionID": "original-id",
        "event": "SessionStart",
        "timestamp": ISO8601DateFormatter().string(from: Date()),
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 200)
}

@Test func twoHookServersRunSimultaneously() async throws {
    let server1 = HookServer(port: 0)
    let server2 = HookServer(port: 0)

    try await server1.start()
    defer { Task { await server1.stop() } }
    try await server2.start()
    defer { Task { await server2.stop() } }

    let port1 = try #require(await server1.actualPort)
    let port2 = try #require(await server2.actualPort)

    #expect(port1 != port2)
}
