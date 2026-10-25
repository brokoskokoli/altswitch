// SPDX-License-Identifier: MIT

import Foundation
import QuartzCore

/// Timing log for launch and shortcut press, off by default. Turn it on with
/// `defaults write com.stefanrichter.altswitch TimingLog -bool YES` (or ALTSWITCH_TIMING=1),
/// relaunch, then watch with `log stream --predicate 'eventMessage CONTAINS "AltSwitch timing"'`.
enum PerfLog {
    static let isEnabled: Bool =
        ProcessInfo.processInfo.environment["ALTSWITCH_TIMING"] == "1" ||
        UserDefaults.standard.bool(forKey: "TimingLog")

    static func now() -> CFTimeInterval {
        CACurrentMediaTime()
    }

    /// Logs the time since `start` in milliseconds.
    static func log(_ label: String, since start: CFTimeInterval) {
        guard isEnabled else { return }
        NSLog("AltSwitch timing: %@ %.2f ms", label, (CACurrentMediaTime() - start) * 1000)
    }

    /// Logs once the current run loop pass is done, after Core Animation has committed the frame
    /// (SwiftUI lays out and draws there, not in the calling code).
    static func logWhenFrameCommitted(_ label: String, since start: CFTimeInterval) {
        guard isEnabled else { return }
        // Core Animation commits in a beforeWaiting observer of order 2000000; run after it
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, Int.max) { _, _ in
            log(label, since: start)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    @discardableResult
    static func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
        guard isEnabled else { return try block() }
        let start = CACurrentMediaTime()
        defer { log(label, since: start) }
        return try block()
    }
}
