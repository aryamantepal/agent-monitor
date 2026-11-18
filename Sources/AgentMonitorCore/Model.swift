import Foundation

public struct Agent: Hashable, Sendable {
    public enum Kind: Sendable { case cli, app }
    public let name: String
    public let kind: Kind

    public init(_ name: String, _ kind: Kind) {
        self.name = name
        self.kind = kind
    }
}

/// One process as read from the kernel, plus rates computed against the previous sample.
public struct Proc: Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32
    /// Seconds since 1970; with `pid` it identifies a process across samples, because pids get reused.
    public var started: Double
    public var command: String
    /// Percent of one core over the last sampling interval (300 = three cores busy).
    public var cpu: Double = 0
    /// Physical footprint in bytes, the number Activity Monitor shows as "Memory".
    public var memory: UInt64 = 0
    /// Kernel-attributed power in watts. An estimate; see README.
    public var watts: Double = 0

    public init(pid: Int32, ppid: Int32, started: Double = 0, command: String,
                cpu: Double = 0, memory: UInt64 = 0, watts: Double = 0) {
        self.pid = pid
        self.ppid = ppid
        self.started = started
        self.command = command
        self.cpu = cpu
        self.memory = memory
        self.watts = watts
    }

    public var identity: ProcID { ProcID(pid: pid, started: started) }
}

public struct ProcID: Hashable, Sendable {
    public let pid: Int32
    public let started: Double
}

public struct Activity: Sendable, Equatable {
    public let proc: Proc
    public let summary: String
    public let place: String

    public init(proc: Proc, summary: String, place: String) {
        self.proc = proc
        self.summary = summary
        self.place = place
    }
}

public struct Session: Sendable, Identifiable {
    /// Stable across samples: the agent name for apps, root pid and start time for CLIs.
    public let id: String
    public let agent: Agent
    public let root: Proc
    /// Short form of the working directory for CLI sessions, empty for apps.
    public let label: String
    public let procs: [Proc]
    public let activities: [Activity]

    public var cpu: Double { procs.reduce(0) { $0 + $1.cpu } }
    public var memory: UInt64 { procs.reduce(0) { $0 + $1.memory } }
    public var watts: Double { procs.reduce(0) { $0 + $1.watts } }
    public var title: String { label.isEmpty ? agent.name : label }
    /// Everything the agent spawned, minus the agent's own processes. Throttle targets these, so
    /// the agent's UI and model connection stay responsive while its builds and tests slow down.
    public var workers: [Proc] { procs.filter { classify($0.command) == nil } }

    public var status: String {
        if let t = activities.first {
            return "running \(t.summary)" + (t.place.isEmpty ? "" : " in \(t.place)")
        }
        return cpu >= Attribution.busyCPU ? "working" : "idle"
    }
}

public struct AgentGroup: Sendable, Identifiable {
    public let name: String
    public let sessions: [Session]
    public var id: String { name }
    public var cpu: Double { sessions.reduce(0) { $0 + $1.cpu } }
    public var memory: UInt64 { sessions.reduce(0) { $0 + $1.memory } }
    public var watts: Double { sessions.reduce(0) { $0 + $1.watts } }
}

public struct Snapshot: Sendable {
    public let groups: [AgentGroup]
    /// Busy processes that belong to no agent.
    public let other: [Activity]
    /// Every process that belongs to no session, busy or not.
    public var unattributed: [Proc] = []
    public static let empty = Snapshot(groups: [], other: [])

    public var cpu: Double { groups.reduce(0) { $0 + $1.cpu } }
    public var sessions: [Session] { groups.flatMap(\.sessions) }
}
