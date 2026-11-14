import SwiftUI

@main
struct ScanAlarmApp: App {
    @StateObject private var store = AlarmStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
