import Foundation
import SwiftUI

struct ConversationView: View {
    @ObservedObject var store: ConversationStore
    @ObservedObject var dashboard: DashboardStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var input = ""
    @State private var showSettings = false
    @State private var showPrivacyVault = false
    @State private var showSubtitles = true
    @State private var todoExpanded = false
    @State private var didAutoConnect = false
    @FocusState private var inputFocused: Bool

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let primary = Color(red: 0.16, green: 0.39, blue: 0.91)
    private let pageBackground = Color(red: 0.969, green: 0.976, blue: 0.992)

    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()

            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 170, y: -330)

            VStack(spacing: 8) {
                header
                weatherCard
                todayCard
                conversationArea

                if let error = store.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                }

                composer
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                configStore: store.configStore,
                onSave: { config in
                    store.updateConfig(config)
                    refreshDashboard()
                },
                onConnect: { _ in
                    store.connect()
                },
                onAbort: {
                    store.abortSpeaking()
                }
            )
        }
        .sheet(isPresented: $showPrivacyVault) {
            PrivacyVaultView(vault: store.privacyVault) {
                store.clearHistory()
                dashboard.clearSensitiveCache()
            }
        }
        .fullScreenCover(
            item: Binding(
                get: { store.videoRequest },
                set: { request in
                    if request == nil {
                        store.dismissVideo()
                    }
                }
            )
        ) { request in
            VideoPlayerView(request: request) {
                store.dismissVideo()
            }
        }
        .alert(
            "设备激活",
            isPresented: Binding(
                get: { store.activationCode != nil },
                set: { if !$0 { store.dismissActivation() } }
            )
        ) {
            Button("我已激活") {
                store.confirmActivation()
            }
            Button("取消", role: .cancel) {
                store.dismissActivation()
            }
        } message: {
            Text("激活码：\(store.activationCode ?? "")\n请在小安控制台完成设备绑定。")
        }
        .onAppear {
            dashboard.restoreCache(config: store.configStore.config)
            refreshDashboard()
            guard !didAutoConnect else {
                return
            }
            didAutoConnect = true
            if store.state == .idle {
                store.connect()
            }
        }
        .onChange(of: store.configStore.config) { config in
            dashboard.restoreCache(config: config)
            refreshDashboard()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshDashboard()
            }
        }
        .onChange(of: store.state) { state in
            if state == .connected {
                refreshDashboard()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.45, blue: 1.0),
                                Color(red: 0.38, green: 0.26, blue: 0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("安")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .shadow(color: primary.opacity(0.24), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("小安")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(red: 0.09, green: 0.12, blue: 0.18))

                Button(action: toggleConnection) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("连接状态：\(statusText)，点按切换连接")
            }

            Spacer()

            headerButton(
                systemName: showSubtitles
                    ? "captions.bubble.fill"
                    : "captions.bubble",
                accessibilityLabel: showSubtitles ? "隐藏字幕" : "显示字幕"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSubtitles.toggle()
                }
            }

            headerButton(
                systemName: "lock.shield.fill",
                accessibilityLabel: "隐私保险箱"
            ) {
                showPrivacyVault = true
            }

            headerButton(
                systemName: "gearshape.fill",
                accessibilityLabel: "服务器与设备设置"
            ) {
                showSettings = true
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var weatherCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Button {
                refreshDashboard()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateFormatter.string(from: context.date))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                        Text(Self.timeFormatter.string(from: context.date))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("保持好心情，今天也要顺顺利利")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(weatherTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(weatherDetail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 76)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.55, blue: 1.0),
                            Color(red: 0.45, green: 0.36, blue: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.blue.opacity(0.18), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("天气信息，点按刷新")
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    todoExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("待办提醒")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Text("\(dashboard.todayItems.count) 条")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.16))
                            .clipShape(Capsule())

                        Image(systemName: todoExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))
                    }

                    Text(todayHint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(todoExpanded ? 2 : 1)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)

            if todoExpanded {
                Divider()
                    .overlay(.white.opacity(0.18))

                if dashboard.todayItems.isEmpty {
                    Text("暂无记录。你可以对小安说“提醒我下午三点开会”，记录会出现在这里。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.vertical, 3)
                } else {
                    VStack(spacing: 8) {
                        ForEach(dashboard.todayItems) { item in
                            todayItemRow(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.34, blue: 0.82),
                    Color(red: 0.46, green: 0.27, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var conversationArea: some View {
        Group {
            if !showSubtitles {
                hiddenSubtitles
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.messages.isEmpty {
                welcome
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hiddenSubtitles: some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 126, height: 126)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.48, blue: 1.0),
                                Color(red: 0.43, green: 0.29, blue: 0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: primary.opacity(0.22), radius: 18, y: 8)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white)
            }

            Text(statusText)
                .font(.headline)
                .foregroundStyle(Color(red: 0.11, green: 0.15, blue: 0.22))

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSubtitles = true
                }
            } label: {
                Label("显示字幕", systemImage: "captions.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.91, green: 0.94, blue: 1.0))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var welcome: some View {
        VStack(spacing: 9) {
            Spacer(minLength: 18)

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 112, height: 112)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.48, blue: 1.0),
                                Color(red: 0.43, green: 0.29, blue: 0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white)
            }

            Text("你好，我是小安")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(red: 0.11, green: 0.15, blue: 0.22))

            Text("直接说，或点下方麦克风开始聊天")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("唤醒词：小安小安 / 你好小安")
                .font(.caption)
                .foregroundStyle(primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color(red: 0.91, green: 0.94, blue: 1.0))
                .clipShape(Capsule())
                .padding(.top, 4)

            Spacer(minLength: 18)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.messages.count) { _ in
                guard let last = store.messages.last else {
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 7) {
            Button(action: microphoneAction) {
                Image(systemName: microphoneIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(microphoneColor)
                    .clipShape(Circle())
            }
            .accessibilityLabel(microphoneAccessibilityLabel)

            TextField("和小安说点什么…", text: $input)
                .font(.system(size: 15))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 4)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        canSend
                            ? primary
                            : Color(red: 0.73, green: 0.77, blue: 0.84)
                    )
                    .clipShape(Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("发送文字消息")
        }
        .padding(5)
        .background(.white)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }

    private var weatherTitle: String {
        if let weather = dashboard.weather {
            return "\(weather.icon)  \(weather.city)"
        }
        return "☀  \(store.configStore.config.weatherCity)"
    }

    private var weatherDetail: String {
        guard let weather = dashboard.weather else {
            return dashboard.weatherUnavailable
                ? "天气暂不可用 · 点此重试"
                : "天气加载中…"
        }
        return "\(weather.description) \(weather.temperature)°  "
            + "\(weather.minimum)° / \(weather.maximum)°"
    }

    private var todayHint: String {
        if dashboard.isRefreshing && dashboard.todayItems.isEmpty {
            return "正在读取今天的语音记录…"
        }
        guard let item = dashboard.todayItems.first else {
            return "今天还没有语音记录，点一下可展开"
        }
        let title = item.title.isEmpty ? item.content : item.title
        return todoExpanded ? "今天共 \(dashboard.todayItems.count) 条记录" : "\(title) · 点一下查看全部"
    }

    private var statusText: String {
        switch store.state {
        case .idle:
            return "未连接"
        case .connecting:
            return "连接中…"
        case .connected:
            return "已连接"
        case .listening:
            return "正在聆听"
        case .processing:
            return "正在思考"
        case .speaking:
            return "正在回答"
        case .failed:
            return "连接失败，点按重试"
        }
    }

    private var statusColor: Color {
        switch store.state {
        case .connected, .listening, .processing, .speaking:
            return Color(red: 0.10, green: 0.68, blue: 0.40)
        case .connecting:
            return .orange
        case .failed:
            return .red
        case .idle:
            return Color(red: 0.59, green: 0.63, blue: 0.69)
        }
    }

    private var microphoneIcon: String {
        switch store.state {
        case .listening:
            return "stop.fill"
        case .speaking:
            return "speaker.slash.fill"
        case .processing:
            return "ellipsis"
        default:
            return "mic.fill"
        }
    }

    private var microphoneColor: Color {
        switch store.state {
        case .listening:
            return .orange
        case .speaking:
            return .red
        default:
            return primary
        }
    }

    private var microphoneAccessibilityLabel: String {
        switch store.state {
        case .listening:
            return "停止说话"
        case .speaking:
            return "打断回答"
        case .processing:
            return "小安正在思考"
        default:
            return store.isConnected ? "开始说话" : "连接服务器"
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.isConnected
    }

    private func headerButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.30, green: 0.35, blue: 0.44))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.82))
                .clipShape(Circle())
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func todayItemRow(_ item: TodayItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.isReminder ? "⏰" : "📝")
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? item.content : item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !item.title.isEmpty && !item.content.isEmpty {
                    Text(item.content)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                }

                Text(itemTime(item))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 7) {
            if message.role == .user {
                Spacer(minLength: 46)
            } else if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(primary)
                    Text("安")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
            }

            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: 3
            ) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundStyle(
                        message.role == .user ? Color.white : Color.primary
                    )
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(messageBackground(for: message.role))
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                Text(Self.timeFormatter.string(from: message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user {
                Spacer(minLength: 46)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.role == .user ? .trailing : .leading
        )
    }

    private func messageBackground(for role: ChatMessage.Role) -> Color {
        switch role {
        case .user:
            return primary
        case .assistant:
            return .white
        case .system:
            return Color(red: 0.91, green: 0.92, blue: 0.95)
        }
    }

    private func itemTime(_ item: TodayItem) -> String {
        let seconds = TimeInterval(item.displayTimeMs) / 1000
        guard seconds > 0 else {
            return item.isReminder ? "待提醒" : "今天"
        }
        return Self.timeFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func toggleConnection() {
        if store.isConnected || store.state == .connecting {
            store.disconnect()
        } else {
            store.connect()
        }
    }

    private func microphoneAction() {
        if store.state == .speaking {
            store.abortSpeaking()
            return
        }
        guard store.isConnected else {
            store.connect()
            return
        }
        Task {
            await store.toggleListening()
        }
    }

    private func send() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        guard store.isConnected else {
            store.errorMessage = "请先连接服务器"
            return
        }
        input = ""
        inputFocused = false
        Task {
            await store.sendText(value)
        }
    }

    private func refreshDashboard() {
        let config = store.configStore.config
        Task {
            await dashboard.refresh(config: config)
        }
    }
}
