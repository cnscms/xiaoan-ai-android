import SwiftUI

@main
struct XiaoZhiAIApp: App {
    @StateObject private var configStore: AppConfigStore
    @StateObject private var conversationStore: ConversationStore

    init() {
        let configStore = AppConfigStore()
        _configStore = StateObject(wrappedValue: configStore)
        _conversationStore = StateObject(
            wrappedValue: ConversationStore(configStore: configStore)
        )
    }

    var body: some Scene {
        WindowGroup {
            ConversationView(store: conversationStore)
                .preferredColorScheme(.light)
        }
    }
}
