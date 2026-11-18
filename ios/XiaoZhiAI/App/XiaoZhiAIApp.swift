import SwiftUI

@main
struct XiaoZhiAIApp: App {
    @StateObject private var configStore: AppConfigStore
    @StateObject private var conversationStore: ConversationStore
    @StateObject private var dashboardStore: DashboardStore
    @StateObject private var privacyVaultStore: PrivacyVaultStore

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
    }

    var body: some Scene {
        WindowGroup {
            ConversationView(
                store: conversationStore,
                dashboard: dashboardStore
            )
                .preferredColorScheme(.light)
        }
    }
}
