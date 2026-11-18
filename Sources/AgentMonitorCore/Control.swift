import Darwin
import Foundation

/// Throttle, pause and kill for a whole session. Signals and scheduling policy apply to one pid
/// at a time and are not inherited by children that already exist, so every operation walks the
/// session's process tree.
public enum Control {
    /// Darwin background policy: lowest CPU priority, efficiency cores, throttled disk and network
    /// I/O. Children forked afterwards inherit it; existing ones don't, so call this every poll.
    @discardableResult
    public static func setThrottled(_ procs: [Proc], _ on: Bool) -> Int {
        procs.filter { $0.pid != getpid() }.reduce(0) { failures, p in
            failures + (setpriority(PRIO_DARWIN_PROCESS, id_t(p.pid), on ? PRIO_DARWIN_BG : 0) == 0 ? 0 : 1)
        }
    }

    /// getpriority() won't report the background flag for other processes, so read the scheduler
    /// priority instead: background-policy threads run at MAXPRI_THROTTLE (4).
    public static func isThrottled(_ pid: Int32) -> Bool {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return false }
        return info.pti_priority <= 4
    }

    /// SIGSTOP the session top-down so a running parent cannot spawn children we miss, re-reading
    /// the tree until no new members appear. Returns what was stopped, in stop order.
    public static func pause(members: () -> [Proc]) -> [ProcID] {
        var stopped: [ProcID] = []
        var seen = Set<ProcID>()
        for _ in 0..<8 {
            let fresh = members().filter { !seen.contains($0.identity) && $0.pid != getpid() }
            if fresh.isEmpty { break }
            for p in topDown(fresh) {
                seen.insert(p.identity)
                if kill(p.pid, SIGSTOP) == 0 { stopped.append(p.identity) }
            }
        }
        return stopped
    }

    /// SIGCONT bottom-up, so the parent wakes last into children that are already running.
    public static func resume(_ stopped: [ProcID]) {
        for id in stopped.reversed() where isAlive(id) { kill(id.pid, SIGCONT) }
    }

    /// SIGTERM everything, then SIGKILL whatever is still alive after `grace`. SIGCONT goes with
    /// SIGTERM because a stopped process cannot run its handler until it is continued.
    public static func terminate(_ procs: [Proc], grace: Duration = .seconds(3)) async {
        let targets = topDown(procs.filter { $0.pid != getpid() })
        for p in targets {
            kill(p.pid, SIGTERM)
            kill(p.pid, SIGCONT)
        }
        try? await Task.sleep(for: grace)
        for p in targets where isAlive(p.identity) { kill(p.pid, SIGKILL) }
    }

    /// Same pid and same start time: guards against signalling a recycled pid.
    public static func isAlive(_ id: ProcID) -> Bool {
        guard let info = DarwinSampler.bsdInfo(id.pid) else { return false }
        let started = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6
        return abs(started - id.started) < 0.001
    }

    /// Parents before children, by depth within the given set.
    static func topDown(_ procs: [Proc]) -> [Proc] {
        let byPID = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        func depth(_ p: Proc) -> Int {
            var d = 0
            var seen: Set<Int32> = [p.pid]
            var cur = p.ppid
            while let parent = byPID[cur], seen.insert(cur).inserted {
                d += 1
                cur = parent.ppid
            }
            return d
        }
        return procs.map { ($0, depth($0)) }.sorted { ($0.1, $0.0.pid) < ($1.1, $1.0.pid) }.map(\.0)
    }
}
