import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var localNetwork = LocalNetworkPermission()

    @ViewBuilder private var localNetworkStatus: some View {
        switch localNetwork.status {
        case .unknown:
            EmptyView()
        case .requesting:
            ProgressView().controlSize(.small)
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        case .denied:
            Label("Blocked", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption)
        }
    }

    @State private var needsRestart = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Display name", text: $settings.displayName)
            }
            Section("LiveKit") {
                TextField("Server URL (wss://…)", text: $settings.liveKitURL)
                TextField("API key", text: $settings.liveKitAPIKey)
                SecureField("API secret", text: $settings.liveKitAPISecret)
            }
            Section("Unblu") {
                TextField("Base URL", text: $settings.unbluBaseURL)
                TextField("Username", text: $settings.unbluUsername)
                SecureField("Password", text: $settings.unbluPassword)
                Text("Reading chat history requires an ADMIN-level account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Testing") {
                Toggle("Join as the exact Unblu person", isOn: $settings.exactIdentity)
                Text("Unblu's call UI only shows a participant whose LiveKit identity matches a person it already has in the call, so this is needed to appear there. A LiveKit identity is exclusive: joining this way evicts that person's Unblu session, and the two will keep evicting each other. For testing only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Button("Request Local Network Access") { localNetwork.request() }
                    // Stored values survive reinstalling, the keychain ones
                    // especially, so there has to be a way back to the
                    // built-in defaults.
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                        needsRestart = true
                    }
                    if needsRestart {
                        Text("Quit and reopen UnbluMeet to pick the defaults up.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    localNetworkStatus
                }
                Text("Needed to reach an Unblu server on your LAN. macOS only asks once; if it was denied, enable UnbluMeet under Privacy & Security > Local Network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
