import Foundation

/// Groups a process table into agent sessions.
///
/// Every process belongs to the nearest ancestor that is a session root. A session root is an
/// agent process whose nearest agent ancestor is not the same agent: each Claude Code or
/// cursor-agent CLI is its own session, while an app and all its helpers collapse into one.
public enum Attribution {
    /// A non-agent process counts as "doing something" above this CPU %.
    public static let busyCPU = 5.0
    /// Unattributed processes are listed above this CPU %.
    public static let otherCPU = 30.0
    public static let topActivities = 4

    public static func snapshot(_ list: [Proc], cwd: (Int32) -> String? = { _ in nil }) -> Snapshot {
        let procs = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let agents = procs.compactMapValues { classify($0.command) }

        func ancestors(of pid: Int32) -> UnfoldSequence<Int32, (Int32?, Set<Int32>)> {
            sequence(state: (procs[pid]?.ppid, Set<Int32>())) { state in
                guard let p = state.0, p > 1, procs[p] != nil, !state.1.contains(p) else { return nil }
                state.1.insert(p)
                state.0 = procs[p]?.ppid
                return p
            }
        }

        var roots = Set<Int32>()
        for (pid, agent) in agents {
            if let up = ancestors(of: pid).first(where: { agents[$0] != nil }), let upAgent = agents[up] {
                if agent.kind == .app && upAgent.name == agent.name { continue }
                if agent.kind == .cli && upAgent == agent { continue }
            }
            roots.insert(pid)
        }

        func sessionRoot(of pid: Int32) -> Int32? {
            if roots.contains(pid) { return pid }
            return ancestors(of: pid).first(where: roots.contains)
        }

        // Desktop apps leave orphaned helpers (crashpad, updaters) that become roots of their own;
        // fold each app into one session keyed by name, rooted at its oldest process.
        var members: [String: [Proc]] = [:]
        var rootOf: [String: Proc] = [:]
        var other: [Proc] = []
        for p in list {
            guard let r = sessionRoot(of: p.pid), let root = procs[r], let agent = agents[r] else {
                if p.cpu >= otherCPU { other.append(p) }
                continue
            }
            let key = agent.kind == .app ? agent.name : "\(root.pid)@\(Int(root.started))"
            members[key, default: []].append(p)
            if let current = rootOf[key], (current.started, current.pid) <= (root.started, root.pid) { continue }
            rootOf[key] = root
        }

        func activity(_ p: Proc) -> Activity {
            Activity(proc: p, summary: shortCommand(p.command), place: shortPath(cwd(p.pid)))
        }

        var groups: [String: [Session]] = [:]
        for (key, procs) in members {
            guard let root = rootOf[key], let agent = agents[root.pid] else { continue }
            let busy = procs.filter { agents[$0.pid] == nil && $0.cpu >= busyCPU }
                .sorted { $0.cpu > $1.cpu }
                .prefix(topActivities)
            let session = Session(
                id: key,
                agent: agent,
                root: root,
                label: agent.kind == .cli ? shortPath(cwd(root.pid)) : "",
                procs: procs,
                activities: busy.map(activity)
            )
            groups[agent.name, default: []].append(session)
        }

        let ordered = groups.map { name, sessions in
            AgentGroup(name: name, sessions: sessions.sorted { ($0.cpu, $1.id) > ($1.cpu, $0.id) })
        }.sorted { ($0.cpu, $1.name) > ($1.cpu, $0.name) }
        return Snapshot(groups: ordered, other: other.sorted { $0.cpu > $1.cpu }.map(activity))
    }
}
