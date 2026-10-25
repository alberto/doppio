import Foundation
import IOKit.pwr_mgt

/// Holds an IOKit power assertion that prevents idle sleep while active.
final class SleepBlocker {
    private var assertionID: IOPMAssertionID = 0
    private var currentType: String?

    var isHolding: Bool { currentType != nil }

    /// Acquires (or swaps) the assertion. `keepDisplayOn` prevents display sleep too.
    func hold(keepDisplayOn: Bool, reason: String) {
        let type = keepDisplayOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        if currentType == type { return }
        release()

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            currentType = type
        }
    }

    func release() {
        guard currentType != nil else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        currentType = nil
    }

    deinit { release() }
}
