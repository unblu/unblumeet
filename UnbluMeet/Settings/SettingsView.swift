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

            Section("Permissions") {
                HStack {
                    Button("Request Local Network Access") { localNetwork.request() }
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
