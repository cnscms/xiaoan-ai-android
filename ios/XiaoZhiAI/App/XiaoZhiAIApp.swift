import SwiftUI

@main
struct XiaoZhiAIApp: App {
    @StateObject private var configStore: AppConfigStore
    @StateObject private var conversationStore: ConversationStore
    @StateObject private var dashboardStore: DashboardStore

    init() {
        let configStore = AppConfigStore()
        _configStore = StateObject(wrappedValue: configStore)
        _conversationStore = StateObject(
            wrappedValue: ConversationStore(configStore: configStore)
        )
        _dashboardStore = StateObject(wrappedValue: DashboardStore())
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
