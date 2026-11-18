import Testing
@testable import AgentMonitorCore

private let claude = "/Users/me/.local/share/claude/versions/2.1.0/claude --dangerously-skip-permissions"
private let cursorMain = "/Applications/Cursor.app/Contents/MacOS/Cursor"
private let cursorHelper = "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Renderer).app/Contents/MacOS/Cursor Helper (Renderer) --type=renderer"

private func p(_ pid: Int32, _ ppid: Int32, _ command: String, cpu: Double = 0, mem: UInt64 = 0) -> Proc {
    Proc(pid: pid, ppid: ppid, started: Double(pid), command: command, cpu: cpu, memory: mem)
}

@Test func classifiesAgents() {
    #expect(classify(claude) == Agent("Claude Code", .cli))
    #expect(classify("claude") == Agent("Claude Code", .cli))
    #expect(classify(cursorHelper) == Agent("Cursor", .app))
    #expect(classify("/usr/local/bin/cursor-agent --resume") == Agent("Cursor", .cli))
    #expect(classify("/Users/me/.codex/bin/codex app-server") == Agent("Codex", .app))
    #expect(classify("/Applications/Claude.app/Contents/MacOS/Claude") == Agent("Claude Desktop", .app))
    #expect(classify("/Applications/Antigravity.app/Contents/MacOS/Electron") == Agent("Antigravity", .app))
    #expect(classify("node /Users/me/claude-tools/index.js") == nil)
    #expect(classify("/bin/zsh -c claude-ish") == nil)
}

@Test func nestedProcessesBelongToTheirNearestSession() {
    let table = [
        p(100, 1, "/bin/zsh"),
        p(200, 100, claude, cpu: 10),
        p(210, 200, "/bin/zsh -c npm test", cpu: 1),
        p(220, 210, "node /repo/node_modules/.bin/vitest run", cpu: 150, mem: 500),
        // Claude Code spawns copies of its own binary; those fold into the parent session.
        p(300, 210, claude, cpu: 4),
        p(310, 300, "cargo build --release", cpu: 300),
        p(400, 100, claude, cpu: 2),
        p(900, 1, "/usr/bin/yes", cpu: 99),
    ]
    let cwd: (Int32) -> String? = { [200: "/Users/me/web", 400: "/Users/me/web/.claude/worktrees/abc", 220: "/Users/me/web"][$0] }
    let snap = Attribution.snapshot(table, cwd: cwd)

    #expect(snap.groups.map(\.name) == ["Claude Code"])
    let sessions = snap.groups[0].sessions
    #expect(sessions.map(\.root.pid) == [200, 400])
    #expect(sessions[0].label == "web")
    #expect(sessions[1].label == "web (worktree)")
    #expect(Set(sessions[0].procs.map(\.pid)) == [200, 210, 220, 300, 310])
    #expect(sessions[0].cpu == 465)
    #expect(sessions[0].activities.map(\.proc.pid) == [310, 220])
    #expect(sessions[0].status == "running cargo build")
    #expect(sessions[1].status == "idle")
    #expect(Set(sessions[0].workers.map(\.pid)) == [210, 220, 310], "agent processes 200 and 300 are not workers")
    #expect(snap.other.map(\.proc.pid) == [900])
}

@Test func appHelpersAndOrphansFoldIntoOneSession() {
    let table = [
        p(500, 1, cursorMain, cpu: 5),
        p(510, 500, cursorHelper, cpu: 20),
        p(520, 510, "/bin/zsh -l", cpu: 0),
        p(530, 520, "python train.py", cpu: 80),
        // Crashpad handler reparented to launchd after its parent restarted.
        p(600, 1, "/Applications/Cursor.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler", cpu: 1),
    ]
    let snap = Attribution.snapshot(table)
    #expect(snap.groups.count == 1)
    let s = snap.groups[0].sessions
    #expect(s.count == 1)
    #expect(s[0].id == "Cursor")
    #expect(s[0].root.pid == 500)
    #expect(s[0].label == "")
    #expect(s[0].procs.count == 5)
    #expect(s[0].cpu == 106)
}

@Test func cursorAgentCLIInsideCursorAppIsItsOwnSession() {
    let table = [
        p(500, 1, cursorMain),
        p(510, 500, "/bin/zsh"),
        p(520, 510, "/usr/local/bin/cursor-agent", cpu: 30),
    ]
    let s = Attribution.snapshot(table).groups[0].sessions
    #expect(Set(s.map(\.root.pid)) == [500, 520])
}

@Test func survivesParentCycles() {
    let table = [p(10, 11, "a", cpu: 50), p(11, 10, "b", cpu: 50)]
    let snap = Attribution.snapshot(table)
    #expect(snap.groups.isEmpty)
    #expect(snap.other.count == 2)
}

@Test func shortFormatting() {
    #expect(shortCommand("node /a/b/vitest.mjs run --watch extra more") == "node vitest.mjs run extra")
    #expect(shortPath("/Users/me", home: "/Users/me") == "~")
    #expect(shortPath("/Users/me/code/forge/", home: "/Users/me") == "forge")
    #expect(shortPath(nil) == "")
}

@Test func parsesProcArgs() {
    var bytes: [UInt8] = withUnsafeBytes(of: Int32(3)) { Array($0) }
    func cString(_ s: String) -> [UInt8] { Array(s.utf8) + [0] }
    bytes += cString("/usr/bin/node") + [0, 0]
    for arg in ["node", "server.js", "--port=3", "PATH=/bin"] { bytes += cString(arg) }
    #expect(DarwinSampler.parseProcArgs(bytes[...]) == "node server.js --port=3")
}

@Test func topDownOrdersParentsFirst() {
    let procs = [p(3, 2, "c"), p(1, 0, "a"), p(2, 1, "b"), p(9, 1, "d")]
    #expect(Control.topDown(procs).map(\.pid) == [1, 2, 9, 3])
}

@Test func sessionsCollectListeningPortsFromAllMembers() {
    let table = [
        p(200, 100, claude),
        p(210, 200, "node next dev"),
        p(220, 210, "node worker"),
        p(900, 1, "nginx"),
    ]
    // 200 is the agent's own IDE port; 55000 is ephemeral; 900 belongs to no session.
    let ports: (Int32) -> [UInt16] = { [200: [8123], 210: [3000], 220: [3000, 9229, 55000], 900: [80]][$0] ?? [] }
    let s = Attribution.snapshot(table, ports: ports).sessions
    #expect(s.count == 1)
    #expect(s[0].ports == [3000, 9229])
}
