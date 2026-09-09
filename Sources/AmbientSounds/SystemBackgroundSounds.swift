import Foundation
import ObjectiveC.runtime
import Darwin

/// A runtime-only bridge to macOS's Background Sounds settings.
/// No private framework is linked into the executable; unsupported systems fail gracefully.
final class SystemBackgroundSounds {
    enum BridgeError: LocalizedError {
        case unavailable
        case soundUnavailable

        var errorDescription: String? {
            switch self {
            case .unavailable: return "The macOS Background Sounds service is unavailable."
            case .soundUnavailable: return "macOS could not prepare this sound."
            }
        }
    }

    struct Snapshot {
        var isEnabled: Bool
        var volume: Double
        var selectedGroup: Int
        var timerEnabled: Bool
        var timerEnd: Date?
    }

    private let frameworkPath = "/System/Library/PrivateFrameworks/HearingUtilities.framework/HearingUtilities"
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var settings: NSObject?

    init() {
        frameworkHandle = dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL)
        settings = Self.sharedObject(className: "HUComfortSoundsSettings", selector: "sharedInstance") as? NSObject
    }

    deinit {
        // The singleton retains types from this image for the process lifetime.
        // Intentionally leave the framework loaded.
    }

    var isAvailable: Bool { frameworkHandle != nil && settings != nil }

    func snapshot() throws -> Snapshot {
        guard let settings else { throw BridgeError.unavailable }

        let enabled = (settings.value(forKey: "comfortSoundsEnabled") as? NSNumber)?.boolValue ?? false
        let volume = (settings.value(forKey: "relativeVolume") as? NSNumber)?.doubleValue ?? 0.35
        let timerEnabled = (settings.value(forKey: "timerEnabled") as? NSNumber)?.boolValue ?? false
        let endValue = (settings.value(forKey: "timerEndInterval") as? NSNumber)?.doubleValue ?? 0
        let selected = settings.value(forKey: "selectedComfortSound") as? NSObject
        let group = (selected?.value(forKey: "soundGroup") as? NSNumber)?.intValue ?? 1
        let end = endValue > Date.timeIntervalSinceReferenceDate
            ? Date(timeIntervalSinceReferenceDate: endValue)
            : nil

        return Snapshot(
            isEnabled: enabled,
            volume: min(max(volume, 0), 1),
            selectedGroup: group,
            timerEnabled: timerEnabled,
            timerEnd: end
        )
    }

    func setEnabled(_ enabled: Bool) throws {
        guard let settings else { throw BridgeError.unavailable }
        settings.setValue(NSNumber(value: enabled), forKey: "comfortSoundsEnabled")
        settings.setValue(NSNumber(value: Date().timeIntervalSince1970), forKey: "lastEnablementTimestamp")
    }

    func setVolume(_ volume: Double) throws {
        guard let settings else { throw BridgeError.unavailable }
        settings.setValue(NSNumber(value: min(max(volume, 0), 1)), forKey: "relativeVolume")
    }

    func select(group: Int) throws {
        guard let settings else { throw BridgeError.unavailable }
        guard let sound = Self.defaultSound(group: group) else { throw BridgeError.soundUnavailable }
        settings.setValue(sound, forKey: "selectedComfortSound")
    }

    func startTimer(minutes: Int) throws {
        guard let settings else { throw BridgeError.unavailable }
        let totalMinutes = max(minutes, 1)
        try Self.setTimer(
            on: settings,
            hours: totalMinutes / 60,
            minutes: totalMinutes % 60
        )
        settings.setValue(NSNumber(value: true), forKey: "timerEnabled")
        try setEnabled(true)
    }

    func cancelTimer() throws {
        guard let settings else { throw BridgeError.unavailable }
        settings.setValue(NSNumber(value: false), forKey: "timerEnabled")
        settings.perform(NSSelectorFromString("resetTimers"))
    }

    private static func sharedObject(className: String, selector selectorName: String) -> AnyObject? {
        guard
            let cls = NSClassFromString(className),
            let method = class_getClassMethod(cls, NSSelectorFromString(selectorName))
        else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return function(cls as AnyObject, NSSelectorFromString(selectorName))?.takeUnretainedValue()
    }

    private static func defaultSound(group: Int) -> NSObject? {
        guard
            let cls = NSClassFromString("HUComfortSound"),
            let method = class_getClassMethod(cls, NSSelectorFromString("defaultComfortSoundForGroup:"))
        else { return nil }

        typealias Function = @convention(c) (AnyObject, Selector, Int) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return function(cls as AnyObject, NSSelectorFromString("defaultComfortSoundForGroup:"), group)?
            .takeUnretainedValue() as? NSObject
    }

    private static func setTimer(on settings: NSObject, hours: Int, minutes: Int) throws {
        guard
            let cls = NSClassFromString("HUComfortSoundsSettings"),
            let method = class_getInstanceMethod(cls, NSSelectorFromString("setTimerInHoursAndMinutes:minutes:"))
        else { throw BridgeError.unavailable }

        typealias Function = @convention(c) (AnyObject, Selector, Int, Int) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(
            settings,
            NSSelectorFromString("setTimerInHoursAndMinutes:minutes:"),
            hours,
            minutes
        )
    }
}
