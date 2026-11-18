import Darwin
import Foundation

public protocol ProcessSampler: AnyObject {
    /// Every process, with CPU % and watts computed against the previous call (zero on the first).
    func sample() -> [Proc]
    func workingDirectory(_ pid: Int32) -> String?
}

/// Reads the process table straight from the kernel through libproc and sysctl.
///
/// The kernel only keeps cumulative counters (CPU time, energy), so rates are deltas between two
/// calls divided by the wall time between them. Not thread-safe: call it from one place.
public final class DarwinSampler: ProcessSampler {
    private struct Counters {
        var cpuNanos: UInt64
        var energyNanojoules: UInt64
    }

    private var previous: [ProcID: Counters] = [:]
    private var previousTime: UInt64 = 0
    private var commands: [ProcID: (comm: String, command: String)] = [:]
    private var argsBuffer: [UInt8]
    private let ticksToNanos: Double

    public init() {
        // CPU times in rusage come in Mach absolute-time ticks. On Intel a tick is 1 ns; on Apple
        // Silicon it is 125/3 ns, so skipping this conversion under-reports CPU by about 40x.
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        ticksToNanos = Double(timebase.numer) / Double(timebase.denom)

        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.argmax", &argmax, &size, nil, 0)
        argsBuffer = [UInt8](repeating: 0, count: Int(max(argmax, 256 * 1024)))
    }

    public func sample() -> [Proc] {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = previousTime == 0 ? 0 : Double(now - previousTime)
        var counters: [ProcID: Counters] = [:]
        var seenCommands: [ProcID: (comm: String, command: String)] = [:]
        var result: [Proc] = []

        for pid in Self.allPIDs() where pid > 0 {
            guard let bsd = Self.bsdInfo(pid) else { continue }
            let started = Double(bsd.pbi_start_tvsec) + Double(bsd.pbi_start_tvusec) / 1e6
            let id = ProcID(pid: pid, started: started)
            let comm = Self.string(bsd.pbi_comm)

            // exec() keeps the pid and start time but changes the command name, so key on both.
            let command: String
            if let cached = commands[id], cached.comm == comm {
                command = cached.command
            } else {
                command = arguments(pid) ?? Self.path(pid) ?? comm
            }
            seenCommands[id] = (comm, command)

            var proc = Proc(pid: pid, ppid: Int32(bsd.pbi_ppid), started: started, command: command)
            if let usage = Self.rusage(pid) {
                let now = Counters(
                    cpuNanos: UInt64(Double(usage.ri_user_time + usage.ri_system_time) * ticksToNanos),
                    energyNanojoules: usage.ri_energy_nj
                )
                counters[id] = now
                proc.memory = usage.ri_phys_footprint
                if elapsed > 0, let before = previous[id] {
                    let cpu = now.cpuNanos &- before.cpuNanos
                    let energy = now.energyNanojoules &- before.energyNanojoules
                    if now.cpuNanos >= before.cpuNanos { proc.cpu = Double(cpu) / elapsed * 100 }
                    if now.energyNanojoules >= before.energyNanojoules { proc.watts = Double(energy) / elapsed }
                }
            }
            result.append(proc)
        }

        previous = counters
        previousTime = now
        commands = seenCommands
        return result
    }

    public func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = Self.string(info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    // MARK: kernel calls

    static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Leave headroom for processes spawned between the two calls.
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(filled, 0))))
    }

    static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    static func rusage(_ pid: Int32) -> rusage_info_v6? {
        var info = rusage_info_v6()
        let ok = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        return ok == 0 ? info : nil
    }

    static func path(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The full argv, joined with spaces like `ps -o command`. Only readable for your own processes.
    func arguments(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = argsBuffer.count
        guard sysctl(&mib, 3, &argsBuffer, &size, nil, 0) == 0 else { return nil }
        return Self.parseProcArgs(argsBuffer[..<size])
    }

    /// Layout: argc (Int32), exec path, NUL padding, then argc NUL-terminated strings.
    static func parseProcArgs(_ buf: ArraySlice<UInt8>) -> String? {
        guard buf.count > 4 else { return nil }
        let start = buf.startIndex
        let argc = buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = start + 4
        while i < buf.endIndex && buf[i] != 0 { i += 1 }
        while i < buf.endIndex && buf[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < argc && i < buf.endIndex {
            let s = i
            while i < buf.endIndex && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[s..<i], as: UTF8.self))
            i += 1
        }
        return args.isEmpty ? nil : args.joined(separator: " ")
    }

    static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
