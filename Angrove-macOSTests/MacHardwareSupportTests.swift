import Testing
@testable import AngroveMac

struct MacHardwareSupportTests {
    @Test func minimumSupportedConfiguration() {
        #expect(MacHardwareSupport(isAppleSilicon: true, physicalMemory: 16 * 1_024 * 1_024 * 1_024, operatingSystemMajorVersion: 27).isSupported)
    }

    @Test func memoryBelowMinimumIsRejected() {
        #expect(!MacHardwareSupport(isAppleSilicon: true, physicalMemory: MacHardwareSupport.minimumMemoryBytes - 1, operatingSystemMajorVersion: 27).isSupported)
    }

    @Test func intelIsRejectedEvenWithEnoughMemory() {
        #expect(!MacHardwareSupport(isAppleSilicon: false, physicalMemory: 32 * 1_024 * 1_024 * 1_024, operatingSystemMajorVersion: 27).isSupported)
    }

    @Test func olderOSIsRejected() {
        #expect(!MacHardwareSupport(isAppleSilicon: true, physicalMemory: MacHardwareSupport.minimumMemoryBytes, operatingSystemMajorVersion: 26).isSupported)
    }

    @Test func newerOSAndMoreMemoryAreAccepted() {
        #expect(MacHardwareSupport(isAppleSilicon: true, physicalMemory: 32 * 1_024 * 1_024 * 1_024, operatingSystemMajorVersion: 28).isSupported)
    }
}
