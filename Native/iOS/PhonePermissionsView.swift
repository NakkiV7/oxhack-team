import SwiftUI
import AVFoundation
import Speech
import UserNotifications

enum PhonePermissionFeature: CaseIterable { case camera, microphone, speech, notifications }
enum PhonePermissionState: String { case notRequested = "Not requested", allowed = "Available", denied = "Not allowed", unavailable = "Unavailable" }
@MainActor protocol PhonePermissionClient {
    func status(_ feature: PhonePermissionFeature) async -> PhonePermissionState
    func request(_ feature: PhonePermissionFeature) async
}
@MainActor struct DevicePhonePermissionClient: PhonePermissionClient {
    func status(_ feature: PhonePermissionFeature) async -> PhonePermissionState {
        switch feature {
        case .camera:
            guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return .allowed
            case .notDetermined: return .notRequested
            default: return .denied
            }
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .allowed
            case .undetermined: return .notRequested
            default: return .denied
            }
        case .speech:
            guard SFSpeechRecognizer(locale: Locale(identifier: "en_GB"))?.supportsOnDeviceRecognition == true else { return .unavailable }
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .allowed
            case .notDetermined: return .notRequested
            default: return .denied
            }
        case .notifications:
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral: return .allowed
            case .notDetermined: return .notRequested
            default: return .denied
            }
        }
    }
    func request(_ feature: PhonePermissionFeature) async {
        guard await status(feature) == .notRequested else { return }
        switch feature {
        case .camera: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone: _ = await AVAudioApplication.requestRecordPermission()
        case .speech: _ = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        case .notifications: _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }
}
@MainActor @Observable final class PhonePermissionStore {
    private let client: any PhonePermissionClient
    private let valid: () -> Bool
    private var requestEpoch = UUID()
    private(set) var camera = PhonePermissionState.notRequested
    private(set) var microphone = PhonePermissionState.notRequested
    private(set) var speech = PhonePermissionState.notRequested
    private(set) var notifications = PhonePermissionState.notRequested
    private(set) var busy = false
    var manualAvailable: Bool { true }
    init(client: (any PhonePermissionClient)? = nil, valid: @escaping () -> Bool = { true }) {
        self.client = client ?? DevicePhonePermissionClient(); self.valid = valid
    }
    func refresh() async {
        let epoch = requestEpoch
        for feature in PhonePermissionFeature.allCases {
            let state = await client.status(feature)
            guard valid(), epoch == requestEpoch, !Task.isCancelled else { return }
            switch feature { case .camera: camera = state; case .microphone: microphone = state; case .speech: speech = state; case .notifications: notifications = state }
        }
    }
    func request(_ feature: PhonePermissionFeature) async {
        guard valid(), !busy else { return }
        let epoch = requestEpoch
        busy = true
        await client.request(feature)
        guard epoch == requestEpoch, valid(), !Task.isCancelled else { busy = false; return }
        await refresh(); busy = false
    }
    func invalidate() { requestEpoch = UUID(); busy = false }
}
struct PhonePermissionsView: View {
    let profileStore: NativeProfileStore
    let healthStore: HealthDataStore
    @State private var permissions: PhonePermissionStore
    init(profileStore: NativeProfileStore, healthStore: HealthDataStore) {
        self.profileStore = profileStore; self.healthStore = healthStore
        _permissions = State(initialValue: PhonePermissionStore(valid: { profileStore.permitsPolicyCallbacks }))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the features you want. Manual logging stays available if you decline.").foregroundStyle(.secondary)
            if (profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0) >= 5 {
                row("Camera sessions", feature: .camera, state: permissions.camera, symbol: "camera")
            }
            row("Spoken logging microphone", feature: .microphone, state: permissions.microphone, symbol: "mic")
            row("On-device speech", feature: .speech, state: permissions.speech, symbol: "waveform")
            row("Scheduled reminders", feature: .notifications, state: permissions.notifications, symbol: "bell")
            if AccountPolicy.allowsHealth(profile: profileStore.profile) {
                NavigationLink { HealthSetupView(store: healthStore) } label: {
                    Label("Choose Apple Health readings", systemImage: "heart.text.square").padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("setup-health")
                Text(healthStore.statusMessage).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Junior activity stays separate from the guardian’s Health records.").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { WatchSetupView() } label: {
                Label("Watch setup or phone only", systemImage: "applewatch").padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("setup-watch")
        }.task { await permissions.refresh() }.onDisappear { permissions.invalidate() }
    }
    private func row(_ title: String, feature: PhonePermissionFeature, state: PhonePermissionState, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            Text(state.rawValue).font(.caption).foregroundStyle(.secondary)
            if state == .notRequested {
                Button("Choose access") { Task { await permissions.request(feature) } }.buttonStyle(.bordered).disabled(permissions.busy)
            } else if state == .denied {
                Text("You can change this in iPhone Settings. Continue with manual logging.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}
