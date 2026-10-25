import Foundation
import IOKit.ps

/// Reports whether the Mac is running on battery below a charge threshold.
final class BatteryMonitor {
    private var runLoopSource: CFRunLoopSource?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().onChange()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    /// True when discharging on battery at or below `percent`. Always false on desktops.
    func isBelow(_ percent: Int) -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        guard providing == kIOPMBatteryPowerKey else { return false }

        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let description = (IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as NSDictionary?) as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return current * 100 / max <= percent
        }
        return false
    }
}
