import Foundation

/// Physical memory is the installed hardware capacity, not currently available memory.
struct MacHardwareSupport: Equatable {
    static let minimumMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024

    let isAppleSilicon: Bool
    let physicalMemory: UInt64
    let operatingSystemMajorVersion: Int

    var isSupported: Bool {
        isAppleSilicon && physicalMemory >= Self.minimumMemoryBytes && operatingSystemMajorVersion >= 27
    }

    static var current: Self {
        #if arch(arm64)
        let isAppleSilicon = true
        #else
        let isAppleSilicon = false
        #endif
        return Self(
            isAppleSilicon: isAppleSilicon,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            operatingSystemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }
}
