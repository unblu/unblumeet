import SwiftUI
import Observation
import os

@Observable
@MainActor
final class LobbyModel {
    var conferences: [ConversationData] = []
    var botPerson: PersonData?
    var error: String?
    var isLoading = false

    private let settings: SettingsStore
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "Lobby")

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private var directory: ConferenceDirectory? {
        guard settings.isUnbluConfigured, let url = URL(string: settings.unbluBaseURL) else { return nil }
        return ConferenceDirectory(client: UnbluClient(baseURL: url,
                                                       username: settings.unbluUsername,
                                                       password: settings.unbluPassword))
    }

    func clearError() {
        error = nil
    }

    func load() async {
        guard let directory else {
            error = "Unblu settings are incomplete. Open Settings (⌘,)."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            botPerson = try await directory.ensureBotPerson(displayName: settings.displayName)
            conferences = try await directory.listConferences()
            logConferences()
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }

    /// Ids are what a LiveKit room is named after, so they are the thing to
    /// quote when comparing what the app joined with what the server holds.
    private func logConferences() {
        logger.info("Loaded \(self.conferences.count, privacy: .public) conferences")
        for conference in conferences {
            let topic = ConferenceDirectory.displayTopic(conference.topic)
            logger.info("  \(conference.id, privacy: .public)  \(topic, privacy: .public)")
        }
    }

    func create(topic: String) async -> ConversationData? {
        guard let directory else { return nil }
        isLoading = true
        defer { isLoading = false }
        do {
            // Not `botPerson ??
            let bot: PersonData
            if let existing = botPerson {
                bot = existing
            } else {
                bot = try await directory.ensureBotPerson(displayName: settings.displayName)
            }
            botPerson = bot

            let agent = try await directory.findAgentPerson()
            let conference = try await directory.createConference(topic: topic, agent: agent, bot: bot)
            logger.info("Created \(conference.id, privacy: .public)  \(topic, privacy: .public)")
            conferences.insert(conference, at: 0)
            error = nil
            return conference
        } catch {
            self.error = "\(error)"
            return nil
        }
    }
}

struct LobbyView: View {
    let settings: SettingsStore
    let onJoin: (ConversationData, PersonData) -> Void

    @State private var model: LobbyModel?
    @State private var newTopic = ""
    @State private var localNetwork = LocalNetworkPermission()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("New conference topic", text: $newTopic)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    Task {
                        if let conference = await model?.create(topic: newTopic) {
                            newTopic = ""
                            join(conference)
                        }
                    }
                }
                .disabled(newTopic.isEmpty)
                Button("Refresh") { Task { await model?.load() } }
            }

            if let error = model?.error {
                HStack(alignment: .top, spacing: 12) {
                    Text(error)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Try again") { Task { await model?.load() } }
                    Button("Dismiss") { model?.clearError() }
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            let conferences = model?.conferences ?? []

            VStack(spacing: 0) {
                ConferenceHeader()
                    .padding(.vertical, 6)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(conferences) { conference in
                            ConferenceRow(conference: conference) { join(conference) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if model?.isLoading == true {
                    ProgressView()
                } else if conferences.isEmpty {
                    Text("No conferences yet — create one above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
        .task {
            // Ask before the first request goes out, so the prompt appears
            // rather than the request silently failing.
            localNetwork.request()
            if model == nil { model = LobbyModel(settings: settings) }
            await model?.load()
        }
    }

    private func join(_ conference: ConversationData) {
        guard let bot = model?.botPerson else { return }
        onJoin(conference, bot)
    }
}
