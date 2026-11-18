import AgentMonitorCore
import Charts
import SwiftUI

struct MenuView: View {
    let monitor: Monitor
    /// False when rendering a screenshot: ImageRenderer can't draw buttons and menus.
    var interactive = true
    var sparklineLength = Monitor.historyLength

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agents").font(.headline)
                Spacer()
                Totals(cpu: snap.cpu, memory: snap.groups.reduce(0) { $0 + $1.memory },
                       watts: snap.groups.reduce(0) { $0 + $1.watts })
            }
            if snap.groups.isEmpty {
                Text("No coding agents running.").foregroundStyle(.secondary)
            }
            ForEach(snap.groups) { group in
                GroupView(group: group, monitor: monitor, interactive: interactive, sparklineLength: sparklineLength)
            }
            if !snap.other.isEmpty {
                Divider()
                Text("Not an agent").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(snap.other, id: \.proc.pid) { a in
                    ActivityRow(activity: a, interactive: interactive) { monitor.kill(a.proc) }
                }
            }
            if interactive {
                Divider()
                Text("CPU: 100% = one core. Power is the kernel's estimate.")
                    .font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    LoginItemToggle()
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                }
            }
        }
        .padding(14)
        .frame(width: 400)
    }
}

struct Totals: View {
    let cpu: Double
    let memory: UInt64
    let watts: Double

    var body: some View {
        Text("\(formatCPU(cpu)) · \(formatMemory(memory)) · \(formatWatts(watts))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

struct GroupView: View {
    let group: AgentGroup
    let monitor: Monitor
    let interactive: Bool
    let sparklineLength: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name).font(.subheadline.weight(.semibold))
                Spacer()
                Totals(cpu: group.cpu, memory: group.memory, watts: group.watts)
            }
            ForEach(group.sessions) { session in
                SessionView(session: session, monitor: monitor, interactive: interactive, sparklineLength: sparklineLength)
            }
        }
    }
}

struct SessionView: View {
    let session: Session
    let monitor: Monitor
    let interactive: Bool
    let sparklineLength: Int

    var body: some View {
        let throttled = monitor.isThrottled(session)
        let paused = monitor.isPaused(session)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.title).font(.callout.weight(.medium)).lineLimit(1)
                        if throttled { Badge(text: "throttled", color: .orange) }
                        if paused { Badge(text: "paused", color: .blue) }
                    }
                    Text(paused ? "paused" : session.status)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Sparkline(values: monitor.history[session.id] ?? [], capacity: sparklineLength,
                          color: throttled ? .orange : .accentColor)
                    .frame(width: 84, height: 26)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCPU(session.cpu)).font(.callout.monospacedDigit())
                    Text(formatMemory(session.memory)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(width: 52, alignment: .trailing)
                if interactive { controls }
            }
            ForEach(session.activities, id: \.proc.pid) { a in
                ActivityRow(activity: a, interactive: interactive) { monitor.kill(a.proc) }
                    .padding(.leading, 10)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        let throttled = monitor.isThrottled(session)
        let paused = monitor.isPaused(session)
        return Menu {
            Button(throttled ? "Stop throttling" : "Throttle (background priority)") {
                monitor.toggleThrottle(session)
            }
            Button(paused ? "Resume" : "Pause (may drop the agent's connection)") {
                monitor.togglePause(session)
            }
            Divider()
            Button("Kill session (\(session.procs.count) processes)", role: .destructive) {
                monitor.kill(session)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ActivityRow: View {
    let activity: Activity
    var interactive = true
    let kill: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(activity.summary).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
            if !activity.place.isEmpty {
                Text(activity.place).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(formatCPU(activity.proc.cpu)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if interactive {
                Button(action: kill) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Kill \(activity.proc.pid)")
            }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct Sparkline: View {
    let values: [Double]
    let capacity: Int
    let color: Color

    var body: some View {
        // Right-align so the newest sample is always at the right edge.
        let offset = capacity - values.count
        let points = values.enumerated().map { (x: offset + $0.offset, y: $0.element) }
        Chart(points, id: \.x) { p in
            AreaMark(x: .value("t", p.x), y: .value("cpu", p.y))
                .foregroundStyle(color.opacity(0.18))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", p.x), y: .value("cpu", p.y))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(capacity - 1, 1))
        .chartYScale(domain: 0...max(100, values.max() ?? 0))
    }
}

func formatCPU(_ v: Double) -> String { "\(Int(v.rounded()))%" }

func formatMemory(_ n: UInt64) -> String {
    let gb = Double(n) / 1_073_741_824
    return gb >= 1 ? String(format: "%.1fG", gb) : String(format: "%.0fM", Double(n) / 1_048_576)
}

func formatWatts(_ w: Double) -> String {
    w >= 10 ? String(format: "~%.0f W", w) : String(format: "~%.1f W", w)
}
