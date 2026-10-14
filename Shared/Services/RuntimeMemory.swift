import Darwin
import Foundation
import os

nonisolated enum LiteRTProbeMemory {
    struct Sample: Encodable, Sendable {
        let physFootprintBytes: UInt64?
        let peakPhysFootprintBytes: Int64?
        let availableMemoryBytes: UInt64
    }

    static func sample() -> Sample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        #if os(iOS)
        let available = UInt64(os_proc_available_memory())
        #else
        var stats = vm_statistics64_data_t()
        var statsCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let hostResult = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(statsCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &statsCount)
            }
        }
        let available = hostResult == KERN_SUCCESS ? UInt64(stats.free_count + stats.inactive_count) * UInt64(getpagesize()) : 0
        #endif
        guard result == KERN_SUCCESS else {
            return Sample(
                physFootprintBytes: nil,
                peakPhysFootprintBytes: nil,
                availableMemoryBytes: available
            )
        }
        return Sample(
            physFootprintBytes: info.phys_footprint,
            peakPhysFootprintBytes: info.ledger_phys_footprint_peak,
            availableMemoryBytes: available
        )
    }
}
