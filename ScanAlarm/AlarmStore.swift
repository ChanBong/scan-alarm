import Foundation
import SwiftUI

/// Settings and ringing state. Everything is derived from a few persisted values,
/// so the app comes back in the right state even after being killed mid-alarm.
@MainActor
final class AlarmStore: ObservableObject {
    /// How long after the alarm time the app still demands a scan.
    static let ringWindow: TimeInterval = 3 * 3600

    @Published private(set) var hour: Int
    @Published private(set) var minute: Int
    @Published private(set) var enabled: Bool
    @Published private(set) var barcode: String?
    @Published private(set) var scheduledAlarms = 0
    @Published private(set) var alarmKitAuthorized = true

    /// When the alarm was last switched on or its time changed.
    private var armedAt: Date
    /// When the barcode was last scanned successfully during a ring.
    private var lastScanAt: Date

    private let defaults = UserDefaults.standard
    private var syncTask: Task<Void, Never>?

    init() {
        hour = defaults.object(forKey: "hour") as? Int ?? 7
        minute = defaults.object(forKey: "minute") as? Int ?? 0
        enabled = defaults.bool(forKey: "enabled")
        barcode = defaults.string(forKey: "barcode")
        armedAt = defaults.object(forKey: "armedAt") as? Date ?? .distantPast
        lastScanAt = defaults.object(forKey: "lastScanAt") as? Date ?? .distantPast
    }

    // MARK: Derived state

    private var timeComponents: DateComponents {
        DateComponents(hour: hour, minute: minute, second: 0)
    }

    func lastOccurrence(before now: Date) -> Date? {
        Calendar.current.nextDate(after: now, matching: timeComponents,
                                  matchingPolicy: .nextTime, direction: .backward)
    }

    func nextOccurrence(after now: Date) -> Date? {
        Calendar.current.nextDate(after: now, matching: timeComponents,
                                  matchingPolicy: .nextTime)
    }

    func isRinging(at now: Date) -> Bool {
        guard enabled, barcode != nil, let last = lastOccurrence(before: now) else { return false }
        return last > armedAt
            && lastScanAt < last
            && now.timeIntervalSince(last) < Self.ringWindow
    }

    // MARK: Actions

    func setTime(hour: Int, minute: Int) {
        guard hour != self.hour || minute != self.minute else { return }
        self.hour = hour
        self.minute = minute
        defaults.set(hour, forKey: "hour")
        defaults.set(minute, forKey: "minute")
        arm()
        sync()
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled, !value || barcode != nil else { return }
        enabled = value
        defaults.set(value, forKey: "enabled")
        if value { arm() }
        sync()
    }

    func setBarcode(_ value: String) {
        barcode = value
        defaults.set(value, forKey: "barcode")
    }

    /// Returns true when the scanned code is the registered one and the alarm is now off.
    func tryDismiss(with code: String) -> Bool {
        guard code == barcode else { return false }
        lastScanAt = Date()
        defaults.set(lastScanAt, forKey: "lastScanAt")
        Ringer.shared.stop()
        sync()
        return true
    }

    /// Called every couple of seconds while the app is on screen.
    func tick(_ now: Date) {
        if isRinging(at: now) {
            Ringer.shared.start()
        } else {
            Ringer.shared.stop()
        }
    }

    /// Rebuilds every scheduled alarm from the current settings.
    func sync() {
        let previous = syncTask
        let hour = hour, minute = minute, enabled = enabled
        let ringing = isRinging(at: Date())
        let next = nextOccurrence(after: Date())
        syncTask = Task { [weak self] in
            await previous?.value
            let result = await AlarmScheduler.apply(hour: hour, minute: minute, enabled: enabled,
                                                    ringing: ringing, nextOccurrence: next)
            self?.scheduledAlarms = result.count
            self?.alarmKitAuthorized = result.authorized
        }
    }

    private func arm() {
        armedAt = Date()
        defaults.set(armedAt, forKey: "armedAt")
    }
}
