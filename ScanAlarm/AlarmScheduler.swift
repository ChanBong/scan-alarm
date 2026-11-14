import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import UserNotifications

struct RingMetadata: AlarmMetadata {}

/// The second button on the system alarm screen: opens the app on the scanner.
struct OpenScannerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Scan to stop"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Schedules the alarm as a chain so that stopping one alarm only buys a minute:
///  - one system alarm repeating daily at the alarm time (survives without the app ever opening),
///  - one system alarm per minute after it,
///  - a notification with a long sound in the gaps between them.
/// Scanning the barcode rebuilds the chain for the next day.
enum AlarmScheduler {
    static let chainLength = 30

    struct Result {
        var count: Int
        var authorized: Bool
    }

    static func apply(hour: Int, minute: Int, enabled: Bool, ringing: Bool,
                      nextOccurrence: Date?, customSound: String?) async -> Result {
        let manager = AlarmManager.shared
        let center = UNUserNotificationCenter.current()

        if let existing = try? manager.alarms {
            for alarm in existing {
                try? manager.cancel(id: alarm.id)
            }
        }
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        guard enabled else { return Result(count: 0, authorized: true) }

        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let state = try? await manager.requestAuthorization()
        let authorized = state == .authorized

        // While ringing, the chain restarts a minute from now; otherwise it follows the next alarm time.
        let now = Date()
        let chainStart: Date
        if ringing {
            chainStart = now.addingTimeInterval(60)
        } else if let next = nextOccurrence {
            chainStart = next.addingTimeInterval(60)
        } else {
            return Result(count: 0, authorized: authorized)
        }

        var count = 0
        if authorized {
            let daily = Alarm.Schedule.relative(.init(
                time: .init(hour: hour, minute: minute),
                repeats: .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
            ))
            if await schedule(daily, sound: customSound) { count += 1 }

            for i in 0..<(chainLength - 1) {
                let date = chainStart.addingTimeInterval(Double(i) * 60)
                guard await schedule(.fixed(date), sound: customSound) else { break }
                count += 1
            }
        }

        for i in 0..<chainLength {
            let date = chainStart.addingTimeInterval(Double(i) * 60 - 30)
            let content = UNMutableNotificationContent()
            content.title = "Alarm"
            content.body = "Open Scan Alarm and scan your barcode to stop it."
            content.sound = UNNotificationSound(named: UNNotificationSoundName(customSound ?? "alarm.wav"))
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "ring-\(i)", content: content, trigger: trigger))
        }

        return Result(count: count, authorized: authorized)
    }

    private static func schedule(_ schedule: Alarm.Schedule, sound: String?) async -> Bool {
        let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        let open = AlarmButton(text: "Scan", textColor: .white, systemImageName: "barcode.viewfinder")
        let alert = AlarmPresentation.Alert(
            title: "Scan your barcode",
            stopButton: stop,
            secondaryButton: open,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<RingMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: RingMetadata(),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<RingMetadata>(
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: OpenScannerIntent(),
            sound: sound.map { AlertConfiguration.AlertSound.named($0) } ?? .default
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            return true
        } catch {
            return false
        }
    }
}
