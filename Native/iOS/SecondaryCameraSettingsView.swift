import SwiftUI
import Observation

@MainActor @Observable
final class SecondaryCameraPairingForm {
    var url = ""
    var certificateSHA256 = ""
    var token = ""
    private(set) var errorMessage: String?
    @ObservationIgnored private let store: any SecondaryCameraSecretStore
    init(store: (any SecondaryCameraSecretStore)? = nil) {
        self.store = store ?? SecondaryCameraKeychainStore()
        do {
            if let saved = try SecondaryCameraSettings.connection(store: self.store) {
                url = saved.configuration.baseURL.absoluteString
                certificateSHA256 = saved.configuration.certificateSHA256
                token = saved.token
            }
        } catch { errorMessage = "Pairing could not be read. Enter the device details again or forget this camera." }
    }
    func save() -> Bool {
        do {
            try SecondaryCameraSettings.save(url: url, certificateSHA256: certificateSHA256, token: token, store: store)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Check the HTTPS address, 64-character certificate fingerprint, and access token. Pairing must also be accessible in this device’s Keychain."
            return false
        }
    }
    func forget() -> Bool {
        do {
            try SecondaryCameraSettings.forget(store: store)
            url = ""; certificateSHA256 = ""; token = ""; errorMessage = nil
            return true
        } catch { errorMessage = "Camera pairing could not be removed from Keychain. Try again after unlocking this device."; return false }
    }
}

struct SecondaryCameraSettingsView: View {
    private enum Field: Hashable { case url, fingerprint, token }
    @Environment(\.dismiss) private var dismiss
    @State private var form = SecondaryCameraPairingForm()
    @FocusState private var focusedField: Field?
    var body: some View {
        NavigationStack {
            Form {
                Section("Private camera pairing") {
                    TextField("HTTPS address", text: $form.url)
                        .focused($focusedField, equals: .url)
                        .accessibilityIdentifier("secondary-camera-address")
                    TextField("Certificate SHA256 fingerprint", text: $form.certificateSHA256, axis: .vertical)
                        .focused($focusedField, equals: .fingerprint)
                        .accessibilityIdentifier("secondary-camera-pin")
                    SecureField("Access token", text: $form.token)
                        .focused($focusedField, equals: .token)
                        .privacySensitive()
                        .accessibilityIdentifier("secondary-camera-token")
                    Text("Enter the private address, certificate fingerprint, and token supplied by your Pi. Pairing stays in this device’s Keychain. Saving does not start the camera.")
                        .font(.caption).foregroundStyle(.secondary)
                        .contentShape(Rectangle()).onTapGesture { focusedField = nil }
                }
                if let error = form.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("secondary-camera-pairing-error")
                }
                Section {
                    Button("Save pairing") { focusedField = nil; if form.save() { dismiss() } }
                        .accessibilityIdentifier("secondary-camera-save")
                    Button("Forget camera", role: .destructive) { focusedField = nil; if form.forget() { dismiss() } }
                        .accessibilityIdentifier("secondary-camera-forget")
                }
            }.scrollDismissesKeyboard(.immediately).accessibilityIdentifier("secondary-camera-settings-form")
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil { KeyboardDismissBar(identifier: "secondary-camera-keyboard-done") { focusedField = nil } }
            }
            .navigationTitle("Side camera")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { focusedField = nil; dismiss() } }
            }
        }
    }
}
