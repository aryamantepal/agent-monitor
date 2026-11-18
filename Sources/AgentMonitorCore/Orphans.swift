import Foundation

/// A process that outlived the agent session that started it, such as a dev server, a headless
/// browser or an MCP server reparented to launchd after its agent exited.
public struct Orphan: Sendable, Identifiable, Equatable {
    public let proc: Proc
    /// Title of the session it came from, e.g. "forge (worktree)".
    public let from: String
    public var id: ProcID { proc.identity }
}

/// Remembers which session each process belonged to, so that when a session ends, the members
/// still alive can be reported as orphans. Never kills anything itself.
public struct OrphanTracker: Sendable {
    /// Processes usually take a moment to exit after their agent does; only report survivors.
    public static let grace: Double = 4

    private var members: [ProcID: (session: String, title: String)] = [:]
    private var orphaned: [ProcID: (from: String, since: Double)] = [:]

    public init() {}

    /// Call once per sample. `now` is in seconds.
    public mutating func update(_ snap: Snapshot, now: Double) -> [Orphan] {
        let live = Set(snap.sessions.map(\.id))
        for (id, m) in members where !live.contains(m.session) && orphaned[id] == nil {
            orphaned[id] = (m.title, now)
        }

        members = [:]
        for s in snap.sessions {
            for p in s.procs { members[p.identity] = (s.id, s.title) }
        }

        // Drop orphans that exited, and any that a live session has adopted again.
        let loose = Dictionary(snap.unattributed.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
        orphaned = orphaned.filter { loose[$0.key] != nil }

        return orphaned.compactMap { id, o in
            guard now - o.since >= Self.grace, let p = loose[id] else { return nil }
            return Orphan(proc: p, from: o.from)
        }
        .sorted { ($0.proc.cpu, $0.proc.memory, $1.proc.pid) > ($1.proc.cpu, $1.proc.memory, $0.proc.pid) }
    }
}
