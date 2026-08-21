import Foundation
import IOKit

enum SystemIdle {
    static func duration() -> Duration {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOHIDSystem"),
                &iterator
            ) == KERN_SUCCESS
        else {
            return .zero
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return .zero }
        defer { IOObjectRelease(entry) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(
                entry,
                &unmanaged,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let properties = unmanaged?.takeRetainedValue() as? [String: Any],
            let idleNanoseconds = properties["HIDIdleTime"] as? UInt64
        else {
            return .zero
        }

        return .nanoseconds(Int64(clamping: idleNanoseconds))
    }
}
