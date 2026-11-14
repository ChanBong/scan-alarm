import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.isRinging(at: now) {
                RingView()
            } else {
                HomeView(now: now)
            }
        }
        .onReceive(timer) { date in
            now = date
            store.tick(date)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .task { refresh() }
    }

    private func refresh() {
        now = Date()
        store.tick(now)
        store.sync()
    }
}

// MARK: - Ringing

struct RingView: View {
    @EnvironmentObject private var store: AlarmStore
    @State private var wrongCode = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Wake up")
                    .font(.system(size: 44, weight: .bold))
                Text("Scan your barcode to stop the alarm.")
                    .font(.headline)

                if ScannerView.isUsable {
                    ScannerView { code in
                        if !store.tryDismiss(with: code) {
                            wrongCode = true
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    Spacer()
                    Text("Camera unavailable. Allow camera access for Scan Alarm in Settings.")
                        .multilineTextAlignment(.center)
                    Spacer()
                }

                Text(wrongCode ? "That is not the registered barcode." : " ")
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }
}

// MARK: - Settings

struct HomeView: View {
    @EnvironmentObject private var store: AlarmStore
    let now: Date
    @State private var registering = false

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: store.hour, minute: store.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.setTime(hour: parts.hour ?? 7, minute: parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alarm") {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    Toggle("Enabled", isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
                        .disabled(store.barcode == nil)
                    if store.enabled, let next = store.nextOccurrence(after: now) {
                        LabeledContent("Next alarm", value: next.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("System alarms queued", value: "\(store.scheduledAlarms)")
                    }
                    if store.enabled && !store.alarmKitAuthorized {
                        Text("Alarm permission is off. Allow alarms for Scan Alarm in Settings, or it can only send notifications.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Barcode") {
                    if let code = store.barcode {
                        LabeledContent("Registered", value: code)
                    } else {
                        Text("Register the barcode you will have to scan. Any barcode or QR code works.")
                            .foregroundStyle(.secondary)
                    }
                    Button(store.barcode == nil ? "Register barcode" : "Change barcode") {
                        registering = true
                    }
                }

                if let expiry = Signing.expiry {
                    Section("App signature") {
                        let days = expiry.timeIntervalSince(now) / 86400
                        LabeledContent("Expires", value: expiry.formatted(date: .abbreviated, time: .shortened))
                        if days < 2 {
                            Text("Refresh the app from your PC soon, or the alarm will stop working.")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Scan Alarm")
            .sheet(isPresented: $registering) {
                RegisterView { code in
                    store.setBarcode(code)
                    registering = false
                }
            }
        }
    }
}

struct RegisterView: View {
    var onScan: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Point the camera at the barcode")
                .font(.headline)
                .padding(.top, 24)
            if ScannerView.isUsable {
                ScannerView(onScan: onScan)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                Spacer()
                Text("Camera unavailable. Allow camera access for Scan Alarm in Settings.")
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding()
    }
}
