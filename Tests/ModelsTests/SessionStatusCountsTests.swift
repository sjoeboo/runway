import Foundation
import Testing

@testable import Models

@Test func statusCountsEmpty() {
    let counts = [Session]().statusCounts
    #expect(counts.running == 0)
    #expect(counts.waiting == 0)
    #expect(counts.idle == 0)
    #expect(counts.error == 0)
}

@Test func statusCountsOneOfEach() {
    let sessions = [
        Session(title: "a", path: "/tmp", status: .running),
        Session(title: "b", path: "/tmp", status: .waiting),
        Session(title: "c", path: "/tmp", status: .idle),
        Session(title: "d", path: "/tmp", status: .error),
    ]
    let counts = sessions.statusCounts
    #expect(counts.running == 1)
    #expect(counts.waiting == 1)
    #expect(counts.idle == 1)
    #expect(counts.error == 1)
}

@Test func statusCountsIgnoresStartingAndStopped() {
    let sessions = [
        Session(title: "a", path: "/tmp", status: .starting),
        Session(title: "b", path: "/tmp", status: .stopped),
        Session(title: "c", path: "/tmp", status: .running),
    ]
    let counts = sessions.statusCounts
    #expect(counts.running == 1)
    #expect(counts.waiting == 0)
    #expect(counts.idle == 0)
    #expect(counts.error == 0)
}

@Test func statusCountsAggregates() {
    let sessions = [
        Session(title: "a", path: "/tmp", status: .running),
        Session(title: "b", path: "/tmp", status: .running),
        Session(title: "c", path: "/tmp", status: .running),
        Session(title: "d", path: "/tmp", status: .idle),
        Session(title: "e", path: "/tmp", status: .idle),
        Session(title: "f", path: "/tmp", status: .error),
    ]
    let counts = sessions.statusCounts
    #expect(counts.running == 3)
    #expect(counts.waiting == 0)
    #expect(counts.idle == 2)
    #expect(counts.error == 1)
}

@Test func statusCountsHasAnyActive() {
    let none = [Session]().statusCounts
    #expect(none.hasAny == false)

    let some = [Session(title: "a", path: "/tmp", status: .idle)].statusCounts
    #expect(some.hasAny == true)

    let onlyStopped = [Session(title: "a", path: "/tmp", status: .stopped)].statusCounts
    #expect(onlyStopped.hasAny == false)
}
