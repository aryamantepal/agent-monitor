import Foundation

/// Machine-readable output for widgets (SketchyBar, tmux, Raycast) and scripts. Keys are
/// snake_case; CPU is percent of one core, memory is bytes, power is estimated watts.
public enum JSONReport {
    struct Root: Encodable {
        let time: Double
        let cpu: Double
        let memory: UInt64
        let watts: Double
        let agents: [Group]
        let other: [Item]
    }

    struct Group: Encodable {
        let name: String
        let cpu: Double
        let memory: UInt64
        let watts: Double
        let sessions: [SessionItem]
    }

    struct SessionItem: Encodable {
        let id: String
        let title: String
        let kind: String
        let pid: Int32
        let status: String
        let cpu: Double
        let memory: UInt64
        let watts: Double
        let processes: Int
        let ports: [UInt16]
        let activities: [Item]
    }

    struct Item: Encodable {
        let pid: Int32
        let command: String
        let summary: String
        let place: String
        let cpu: Double
        let memory: UInt64
    }

    public static func render(_ snap: Snapshot, pretty: Bool, now: Date = Date()) -> String {
        // JSONEncoder throws on NaN or infinity; report those as 0 rather than failing the line.
        func r(_ v: Double) -> Double { v.isFinite ? (v * 10).rounded() / 10 : 0 }
        func item(_ a: Activity) -> Item {
            Item(pid: a.proc.pid, command: a.proc.command, summary: a.summary, place: a.place,
                 cpu: r(a.proc.cpu), memory: a.proc.memory)
        }
        let root = Root(
            time: now.timeIntervalSince1970.rounded(),
            cpu: r(snap.cpu),
            memory: snap.groups.reduce(0) { $0 + $1.memory },
            watts: r(snap.groups.reduce(0) { $0 + $1.watts }),
            agents: snap.groups.map { g in
                Group(name: g.name, cpu: r(g.cpu), memory: g.memory, watts: r(g.watts),
                      sessions: g.sessions.map { s in
                          SessionItem(id: s.id, title: s.title, kind: s.agent.kind == .cli ? "cli" : "app",
                                      pid: s.root.pid, status: s.status, cpu: r(s.cpu), memory: s.memory,
                                      watts: r(s.watts), processes: s.procs.count, ports: s.ports,
                                      activities: s.activities.map(item))
                      })
            },
            other: snap.other.map(item)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        do {
            return String(decoding: try encoder.encode(root), as: UTF8.self)
        } catch {
            FileHandle.standardError.write(Data("agent-monitor: JSON encoding failed: \(error)\n".utf8))
            return "{}"
        }
    }
}
