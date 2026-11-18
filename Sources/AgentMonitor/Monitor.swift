import AgentMonitorCore
import Foundation
import Observation

/// Owns the sampler. An actor so sampling (hundreds of syscalls) stays off the main thread.
actor Engine {
    private let sampler = DarwinSampler()

    func snapshot() -> Snapshot {
        Attribution.snapshot(sampler.sample(), cwd: sampler.workingDirectory)
    }

    func members(of id: String) -> [Proc] {
        Attribution.snapshot(sampler.sample()).sessions.first { $0.id == id }?.procs ?? []
    }

    func pause(_ id: String) -> [ProcID] {
        Control.pause { members(of: id) }
    }
}

@MainActor @Observable
final class Monitor {
    static let interval: Duration = .seconds(2)
    /// 90 samples at 2 s: the sparklines cover the last three minutes.
    static let historyLength = 90

    private(set) var snapshot = Snapshot.empty
    private(set) var history: [String: [Double]] = [:]
    private(set) var throttled: Set<String> = []
    private(set) var paused: [String: [ProcID]] = [:]

    private let engine = Engine()
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Monitor.interval)
            }
        }
    }

    func tick() async {
        let snap = await engine.snapshot()
        let live = Set(snap.sessions.map(\.id))

        // Throttling isn't inherited by children that already exist, and agents spawn new ones
        // constantly, so re-apply it to every member on every poll.
        for session in snap.sessions where throttled.contains(session.id) {
            Control.setThrottled(session.workers, true)
        }
        throttled.formIntersection(live)
        paused = paused.filter { live.contains($0.key) && $0.value.contains(where: Control.isAlive) }

        for session in snap.sessions {
            var values = history[session.id] ?? []
            values.append(session.cpu)
            history[session.id] = Array(values.suffix(Self.historyLength))
        }
        history = history.filter { live.contains($0.key) }
        snapshot = snap
    }

    // MARK: controls

    func isThrottled(_ s: Session) -> Bool { throttled.contains(s.id) }
    func isPaused(_ s: Session) -> Bool { paused[s.id] != nil }

    func toggleThrottle(_ s: Session) {
        if throttled.remove(s.id) != nil {
            Control.setThrottled(s.procs, false)
        } else {
            throttled.insert(s.id)
            Control.setThrottled(s.workers, true)
        }
    }

    func togglePause(_ s: Session) {
        if let stopped = paused.removeValue(forKey: s.id) {
            Control.resume(stopped)
            return
        }
        Task {
            let stopped = await engine.pause(s.id)
            if !stopped.isEmpty { paused[s.id] = stopped }
        }
    }

    func kill(_ s: Session) {
        paused[s.id] = nil
        Task { await Control.terminate(s.procs) }
    }

    func kill(_ p: Proc) {
        Task { await Control.terminate([p]) }
    }
}
