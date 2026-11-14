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
    @Published private(set) var soundName: String?
    @Published private(set) var previewing = false
    @Published private(set) var scheduledAlarms = 0
    @Published private(set) var alarmKitAuthorized = true

    /// When the alarm was last switched on or its time changed.
    private var armedAt: Date
    /// When the barcode was last scanned successfully during a ring.
    private var lastScanAt: Date

    /// Full-length copy of the chosen audio file (in Documents), looped while the app is open.
    private var soundFile: String?
    /// Short PCM clip of it (in Library/Sounds), used by system alarms and notifications.
    private var clipFile: String?

    private let defaults = UserDefaults.standard
    private var syncTask: Task<Void, Never>?

    init() {
        hour = defaults.object(forKey: "hour") as? Int ?? 7
        minute = defaults.object(forKey: "minute") as? Int ?? 0
        enabled = defaults.bool(forKey: "enabled")
        barcode = defaults.string(forKey: "barcode")
        armedAt = defaults.object(forKey: "armedAt") as? Date ?? .distantPast
        lastScanAt = defaults.object(forKey: "lastScanAt") as? Date ?? .distantPast
        soundName = defaults.string(forKey: "soundName")
        soundFile = defaults.string(forKey: "soundFile")
        clipFile = defaults.string(forKey: "clipFile")
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
            previewing = false
            Ringer.shared.start(url: ringURL)
        } else if !previewing {
            Ringer.shared.stop()
        }
    }

    // MARK: Sound

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var soundsFolder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// The file the app loops while ringing: the chosen tune, or the built-in beeps.
    private var ringURL: URL? {
        if let soundFile {
            let url = Self.documents.appendingPathComponent(soundFile)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return Bundle.main.url(forResource: "alarm", withExtension: "wav")
    }

    func importSound(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let newFile = "tune-\(stamp).\(ext)"
        let newClip = "tune-\(stamp).wav"
        let fileURL = Self.documents.appendingPathComponent(newFile)
        let clipURL = Self.soundsFolder.appendingPathComponent(newClip)

        try fm.createDirectory(at: Self.soundsFolder, withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: fileURL)
        do {
            try SoundClip.make(from: fileURL, to: clipURL)
        } catch {
            try? fm.removeItem(at: fileURL)
            try? fm.removeItem(at: clipURL)
            throw error
        }

        stopPreview()
        removeSoundFiles()
        soundFile = newFile
        clipFile = newClip
        soundName = url.lastPathComponent
        saveSound()
        sync()
    }

    func useDefaultSound() {
        stopPreview()
        removeSoundFiles()
        soundFile = nil
        clipFile = nil
        soundName = nil
        saveSound()
        sync()
    }

    func togglePreview() {
        if previewing {
            stopPreview()
        } else {
            previewing = true
            Ringer.shared.start(url: ringURL)
        }
    }

    private func stopPreview() {
        guard previewing else { return }
        previewing = false
        Ringer.shared.stop()
    }

    private func removeSoundFiles() {
        if let soundFile {
            try? FileManager.default.removeItem(at: Self.documents.appendingPathComponent(soundFile))
        }
        if let clipFile {
            try? FileManager.default.removeItem(at: Self.soundsFolder.appendingPathComponent(clipFile))
        }
    }

    private func saveSound() {
        defaults.set(soundName, forKey: "soundName")
        defaults.set(soundFile, forKey: "soundFile")
        defaults.set(clipFile, forKey: "clipFile")
    }

    /// Rebuilds every scheduled alarm from the current settings.
    func sync() {
        let previous = syncTask
        let hour = hour, minute = minute, enabled = enabled
        let ringing = isRinging(at: Date())
        let next = nextOccurrence(after: Date())
        let clip = clipFile
        syncTask = Task { [weak self] in
            await previous?.value
            let result = await AlarmScheduler.apply(hour: hour, minute: minute, enabled: enabled,
                                                    ringing: ringing, nextOccurrence: next,
                                                    customSound: clip)
            self?.scheduledAlarms = result.count
            self?.alarmKitAuthorized = result.authorized
        }
    }

    private func arm() {
        armedAt = Date()
        defaults.set(armedAt, forKey: "armedAt")
    }
}
