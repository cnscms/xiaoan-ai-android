import SwiftUI

@main
struct XiaoZhiAIApp: App {
    @StateObject private var configStore: AppConfigStore
    @StateObject private var conversationStore: ConversationStore
    @StateObject private var dashboardStore: DashboardStore
    @StateObject private var privacyVaultStore: PrivacyVaultStore
    @StateObject private var voiceNotesStore: VoiceNotesStore

    init() {
        let configStore = AppConfigStore()
        let privacyVaultStore = PrivacyVaultStore()
        _configStore = StateObject(wrappedValue: configStore)
        _conversationStore = StateObject(
            wrappedValue: ConversationStore(
                configStore: configStore,
                privacyVault: privacyVaultStore
            )
        )
        _dashboardStore = StateObject(
            wrappedValue: DashboardStore(privacyVault: privacyVaultStore)
        )
        _privacyVaultStore = StateObject(wrappedValue: privacyVaultStore)
        _voiceNotesStore = StateObject(
            wrappedValue: VoiceNotesStore(configStore: configStore)
        )
    }

    var body: some Scene {
        WindowGroup {
            ConversationView(
                store: conversationStore,
                dashboard: dashboardStore,
                voiceNotes: voiceNotesStore
            )
                .preferredColorScheme(.light)
        }
    }
}
