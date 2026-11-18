import Foundation

public enum TextReport {
    public static func render(_ snap: Snapshot) -> String {
        var lines: [String] = []
        func pad(_ s: String, _ n: Int) -> String { String(repeating: " ", count: max(0, n - s.count)) + s }
        func mem(_ n: UInt64) -> String {
            n >= 1 << 30 ? String(format: "%.1fG", Double(n) / Double(1 << 30)) : "\(n >> 20)M"
        }
        func watts(_ w: Double) -> String { String(format: "~%.1fW", w) }
        for g in snap.groups {
            lines.append("\(g.name)  \(Int(g.cpu.rounded()))% CPU  \(mem(g.memory))  \(watts(g.watts))")
            for s in g.sessions {
                lines.append("  \(s.title): \(s.status)  (\(Int(s.cpu.rounded()))%, \(mem(s.memory)), \(s.procs.count) procs)")
                for a in s.activities {
                    lines.append("    \(pad(String(a.proc.pid), 6)) \(pad("\(Int(a.proc.cpu.rounded()))%", 5)) \(pad(mem(a.proc.memory), 5))  \(a.summary)  [\(a.place)]")
                }
            }
        }
        if !snap.other.isEmpty {
            lines.append("Not an agent")
            for a in snap.other {
                lines.append("  \(pad(String(a.proc.pid), 6)) \(pad("\(Int(a.proc.cpu.rounded()))%", 5))  \(a.summary)  [\(a.place)]")
            }
        }
        return lines.isEmpty ? "No coding agents running." : lines.joined(separator: "\n")
    }
}
