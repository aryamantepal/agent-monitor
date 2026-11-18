import Testing
@testable import AgentMonitorCore

private let claude = "/Users/me/.local/share/claude/versions/2.1.0/claude"

@Test func survivorsOfAClosedSessionBecomeOrphansAfterTheGracePeriod() {
    var tracker = OrphanTracker()
    let cwd: (Int32) -> String? = { $0 == 200 ? "/Users/me/forge" : nil }
    let running = [
        Proc(pid: 200, ppid: 100, started: 1, command: claude),
        Proc(pid: 210, ppid: 200, started: 2, command: "node next dev"),
        Proc(pid: 220, ppid: 200, started: 3, command: "node vitest run"),
    ]
    #expect(tracker.update(Attribution.snapshot(running, cwd: cwd), now: 0).isEmpty)

    // Claude exits; next dev is reparented to launchd, vitest is still shutting down.
    let afterExit = [
        Proc(pid: 210, ppid: 1, started: 2, command: "node next dev", memory: 300),
        Proc(pid: 220, ppid: 1, started: 3, command: "node vitest run"),
    ]
    #expect(tracker.update(Attribution.snapshot(afterExit), now: 2).isEmpty, "inside the grace period")

    // vitest finished exiting; next dev is still up.
    let later = [Proc(pid: 210, ppid: 1, started: 2, command: "node next dev", memory: 300)]
    let orphans = tracker.update(Attribution.snapshot(later), now: 6)
    #expect(orphans.map(\.proc.pid) == [210])
    #expect(orphans.first?.from == "forge")

    // Once it exits, it's gone.
    #expect(tracker.update(Attribution.snapshot([]), now: 8).isEmpty)
}

@Test func reusedPIDsAreNotOrphans() {
    var tracker = OrphanTracker()
    _ = tracker.update(Attribution.snapshot([
        Proc(pid: 200, ppid: 100, started: 1, command: claude),
        Proc(pid: 210, ppid: 200, started: 2, command: "node next dev"),
    ]), now: 0)
    _ = tracker.update(Attribution.snapshot([]), now: 2)
    // Same pid, different start time: a new, unrelated process.
    let orphans = tracker.update(Attribution.snapshot([Proc(pid: 210, ppid: 1, started: 50, command: "sshd")]), now: 10)
    #expect(orphans.isEmpty)
}

@Test func liveSessionsProduceNoOrphans() {
    var tracker = OrphanTracker()
    let table = [
        Proc(pid: 200, ppid: 100, started: 1, command: claude),
        Proc(pid: 210, ppid: 200, started: 2, command: "node next dev"),
    ]
    for t in stride(from: 0.0, through: 20, by: 2) {
        #expect(tracker.update(Attribution.snapshot(table), now: t).isEmpty)
    }
}
