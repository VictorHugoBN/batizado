import BatizadoCore
import Darwin
import IOKit
import os

private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "sleep-disabled")

public enum SystemFacts {
    /// The process holding `pid` now, with its start time; nil when no process has that pid.
    public static func process(_ pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let started = Int64(info.pbi_start_tvsec) * 1_000_000 + Int64(info.pbi_start_tvusec)
        return ProcessIdentity(pid: pid, startedAt: started)
    }

    public static var currentProcess: ProcessIdentity? { process(getpid()) }

    /// `kern.boottime` in seconds; 0 if it cannot be read.
    public static var bootTime: Int64 {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        return Int64(boot.tv_sec)
    }

    /// The kernel's root power domain holds the value it actually enforces on lid close; nil when it cannot
    /// be read, which callers must never treat as 0.
    public static var sleepDisabled: Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else {
            log.error("IOPMrootDomain not found; SleepDisabled is unknown")
            return nil
        }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(
            root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        guard let disabled = value as? Bool else {
            log.error("IOPMrootDomain has no SleepDisabled; SleepDisabled is unknown")
            return nil
        }
        log.info("SleepDisabled is \(disabled ? 1 : 0)")
        return disabled
    }
}

extension Optional where Wrapped == Bool {
    /// "1", "0" or "unknown", for logs.
    public var sleepDisabledText: String { map { $0 ? "1" : "0" } ?? "unknown" }
}
