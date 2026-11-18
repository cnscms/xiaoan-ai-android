import SwiftUI

struct ConversationView: View {
    @ObservedObject var store: ConversationStore
    @State private var input = ""
    @State private var showSettings = false
    @State private var showSubtitles = true
    @FocusState private var inputFocused: Bool

    private var isConnected: Bool {
        store.sessionID != nil
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.973, green: 0.976, blue: 1.0),
                    Color(red: 0.984, green: 0.961, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(y: -200)

            VStack(spacing: 18) {
                header

                if showSubtitles && !store.messages.isEmpty {
                    messageList
                } else {
                    Spacer()
                    orb
                }

                if let error = store.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                inputBar
                callControls
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(configStore: store.configStore) { config in
                store.updateConfig(config)
                showSettings = false
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
    }

    private var header: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("设置")

            Spacer()

            Text("小安")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.40, green: 0.29, blue: 0.71))

            Spacer()

            Button {
                showSubtitles.toggle()
            } label: {
                Image(systemName: showSubtitles ? "captions.bubble.fill" : "captions.bubble")
            }
            .accessibilityLabel("字幕")
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private var orb: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.81, green: 0.71, blue: 1.0),
                                Color(red: 0.43, green: 0.29, blue: 0.78)
                            ],
                            center: .topLeading,
                            startRadius: 20,
                            endRadius: 180
                        )
                    )
                    .frame(width: 230, height: 230)
                    .shadow(color: .purple.opacity(0.24), radius: 28, y: 16)

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text(stateTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(red: 0.07, green: 0.11, blue: 0.16))

            Text("OTA、绑定、文字协议和 Opus 语音链路已接入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        HStack {
                            if message.role == .user {
                                Spacer(minLength: 48)
                            }
                            Text(message.content)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .foregroundColor(
                                    message.role == .user ? Color.white : Color.primary
                                )
                                .background(
                                    message.role == .user
                                        ? Color(red: 0.40, green: 0.29, blue: 0.71)
                                        : Color.white.opacity(0.86)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .id(message.id)
                            if message.role != .user {
                                Spacer(minLength: 48)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: store.messages) { messages in
                guard let last = messages.last else {
                    return
                }
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("输入文字消息", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(!isConnected || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var callControls: some View {
        HStack(spacing: 32) {
            Button {
                if isConnected {
                    store.disconnect()
                } else {
                    store.connect()
                }
            } label: {
                Image(systemName: isConnected ? "xmark" : "phone.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(isConnected ? Color.red : Color.green)
                    .clipShape(Circle())
                    .shadow(radius: 10, y: 5)
            }
            .accessibilityLabel(isConnected ? "断开" : "连接")

            if isConnected {
                Button {
                    Task {
                        await store.toggleListening()
                    }
                } label: {
                    Image(
                        systemName: store.state == .listening
                            ? "stop.fill"
                            : "mic.fill"
                    )
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(
                        store.state == .listening
                            ? Color.orange
                            : Color(red: 0.40, green: 0.29, blue: 0.71)
                    )
                    .clipShape(Circle())
                    .shadow(radius: 10, y: 5)
                }
                .accessibilityLabel(
                    store.state == .listening ? "停止说话" : "开始说话"
                )
            }
        }
    }

    private var stateTitle: String {
        switch store.state {
        case .idle:
            return isConnected ? "准备就绪" : "点击后开始对话"
        case .connecting:
            return "连接中…"
        case .connected:
            return "在线"
        case .listening:
            return "正在聆听…"
        case .processing:
            return "正在思考…"
        case .speaking:
            return "正在回答…"
        case let .failed(message):
            return message
        }
    }

    private func send() {
        let value = input
        input = ""
        inputFocused = false
        Task {
            await store.sendText(value)
        }
    }
}

