import Darwin
import Foundation

/// Lifecycle and timing lines for `devicectl --console` (Debug builds), and
/// the process's memory footprint for the sequence log.
nonisolated enum CaptureLog {
    static func event(_ line: String) {
        #if DEBUG
        print("CAPTURE| " + line)
        fflush(stdout)
        #endif
    }

    /// Physical footprint in bytes (what jetsam counts), from `task_info`.
    static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}
