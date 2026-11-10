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
    @State private var watch = WatchSetupStore()
    @State private var voiceExpanded = false
    init(profileStore: NativeProfileStore, healthStore: HealthDataStore, permissions: PhonePermissionStore? = nil) {
        self.profileStore = profileStore; self.healthStore = healthStore
        _permissions = State(initialValue: permissions ?? PhonePermissionStore(valid: { profileStore.permitsPolicyCallbacks }))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose the features you want. Manual logging stays available if you decline.")
                .font(.subheadline).foregroundStyle(.secondary)
            if (profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0) >= 5 {
                PhonePermissionRow(title: "Camera sessions", feature: .camera, state: permissions.camera, symbol: "camera", permissions: permissions)
            }
            if AccountPolicy.allowsHealth(profile: profileStore.profile) {
                NavigationLink { HealthSetupView(store: healthStore) } label: {
                    permissionLink("Choose Apple Health readings", detail: healthStore.statusMessage, symbol: "heart.text.square")
                }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("setup-health")
            } else {
                Label("Junior activity stays separate from the guardian’s Health records.", systemImage: "heart.text.square")
                    .font(.subheadline).foregroundStyle(.secondary).padding(14)
            }
            NavigationLink { WatchSetupView() } label: {
                permissionLink("Watch setup or phone only", detail: watch.selectedModel == .noWatch ? "Phone only" : watch.presentation.summary, symbol: "applewatch")
            }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("setup-watch")
            VoiceLoggingPermissionDisclosure(permissions: permissions, isExpanded: $voiceExpanded)
        }.task { await permissions.refresh(); watch.refresh() }.onDisappear { permissions.invalidate() }
    }
    private func permissionLink(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct VoiceLoggingPermissionDisclosure: View {
    let permissions: PhonePermissionStore
    @Binding var isExpanded: Bool
    var body: some View {
        DisclosureGroup("Voice logging and reminders", isExpanded: $isExpanded) {
            VStack(spacing: 12) {
                PhonePermissionRow(title: "Spoken logging microphone", feature: .microphone, state: permissions.microphone, symbol: "mic", permissions: permissions)
                PhonePermissionRow(title: "On-device speech", feature: .speech, state: permissions.speech, symbol: "waveform", permissions: permissions)
                PhonePermissionRow(title: "Scheduled reminders", feature: .notifications, state: permissions.notifications, symbol: "bell", permissions: permissions)
            }.padding(.top, 12)
        }.frame(minHeight: 44).accessibilityIdentifier("setup-voice-reminders")
    }
}

struct PhonePermissionRow: View {
    let title: String
    let feature: PhonePermissionFeature
    let state: PhonePermissionState
    let symbol: String
    let permissions: PhonePermissionStore
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                heading
                accessButton
            } else {
                HStack(spacing: 12) { heading; Spacer(minLength: 0); accessButton }
            }
            if state == .denied {
                Text("Change access in iPhone Settings or continue with manual logging.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private var heading: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(state.rawValue).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var accessButton: some View {
        if state == .notRequested {
            Button("Choose access") { Task { await permissions.request(feature) } }
                .buttonStyle(.bordered).disabled(permissions.busy).frame(minHeight: 44)
                .accessibilityLabel("Choose \(title) access")
        }
    }
}
