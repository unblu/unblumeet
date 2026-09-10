import SwiftUI

@main
struct UnbluMeetApp: App {
    @State private var settings = SettingsStore()
    @State private var joined: (conversation: ConversationData, bot: PersonData)?

    var body: some Scene {
        WindowGroup {
            if let joined {
                ConferenceView(settings: settings,
                               conversationId: joined.conversation.id,
                               topic: ConferenceDirectory.displayTopic(joined.conversation.topic),
                               identity: joined.bot.id,
                               onLeave: { self.joined = nil })
            } else {
                LobbyView(settings: settings) { conversation, bot in
                    joined = (conversation, bot)
                }
            }
        }
        Settings {
            SettingsView(settings: settings)
        }
    }
}
