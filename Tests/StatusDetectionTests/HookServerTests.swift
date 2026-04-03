import Foundation
import Testing

@testable import StatusDetection

@Test func hookServerStartsAndExposesPort() async throws {
    let server = HookServer(port: 0)
    try await server.start()

    let port = await server.actualPort
    #expect(port != nil)
    #expect(port! > 0)

    await server.stop()
}

@Test func hookServerAcceptsConnections() async throws {
    let server = HookServer(port: 0)
    try await server.start()

    let port = await server.actualPort
    let portValue = try #require(port)

    // Send a minimal HTTP POST to the server
    let url = URL(string: "http://127.0.0.1:\(portValue)/hooks")!
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

    await server.stop()
}

@Test func twoHookServersRunSimultaneously() async throws {
    let server1 = HookServer(port: 0)
    let server2 = HookServer(port: 0)

    try await server1.start()
    try await server2.start()

    let port1 = await server1.actualPort
    let port2 = await server2.actualPort

    #expect(port1 != nil)
    #expect(port2 != nil)
    #expect(port1 != port2)

    await server1.stop()
    await server2.stop()
}
