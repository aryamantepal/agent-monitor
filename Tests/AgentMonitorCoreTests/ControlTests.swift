import Darwin
import Foundation
import Testing
@testable import AgentMonitorCore

/// Spawns `sh` with two busy `yes` children and returns the whole tree.
private func spawnTree() throws -> (Process, () -> [Proc]) {
    let sh = Process()
    sh.executableURL = URL(fileURLWithPath: "/bin/sh")
    sh.arguments = ["-c", "yes >/dev/null & yes >/dev/null & wait"]
    try sh.run()
    let sampler = DarwinSampler()
    let tree = { () -> [Proc] in
        let all = sampler.sample()
        let kids = all.filter { $0.ppid == sh.processIdentifier }
        return all.filter { $0.pid == sh.processIdentifier } + kids
    }
    for _ in 0..<50 where tree().count < 3 { usleep(20_000) }
    return (sh, tree)
}

private func state(_ pid: Int32) -> String {
    let ps = Process()
    let out = Pipe()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-o", "stat=", "-p", String(pid)]
    ps.standardOutput = out
    try? ps.run()
    ps.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

@Test func pauseResumeThrottleAndKillAWholeTree() async throws {
    let (sh, tree) = try spawnTree()
    let procs = tree()
    try #require(procs.count == 3)

    let stopped = Control.pause(members: tree)
    #expect(stopped.count == 3)
    #expect(stopped.first?.pid == sh.processIdentifier, "parent is stopped first")
    for p in procs { #expect(state(p.pid).hasPrefix("T"), "pid \(p.pid) stopped") }

    Control.resume(stopped)
    for p in procs { #expect(!state(p.pid).hasPrefix("T"), "pid \(p.pid) running") }

    #expect(Control.setThrottled(procs, true) == 0)
    for p in procs { #expect(Control.isThrottled(p.pid)) }
    Control.setThrottled(procs, false)
    for p in procs { #expect(!Control.isThrottled(p.pid)) }

    // Kill while paused: SIGTERM alone would sit pending on a stopped process.
    _ = Control.pause(members: tree)
    await Control.terminate(procs, grace: .milliseconds(500))
    sh.waitUntilExit()
    for p in procs { #expect(!Control.isAlive(p.identity)) }
}

@Test func readsListeningPortsOfARealProcess() throws {
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    server.arguments = ["-c", "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); print(s.getsockname()[1], flush=True); time.sleep(30)"]
    let out = Pipe()
    server.standardOutput = out
    try server.run()
    defer { server.terminate() }
    let line = out.fileHandleForReading.availableData
    let port = try #require(UInt16(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(DarwinSampler().listeningPorts(server.processIdentifier) == [port])
}
