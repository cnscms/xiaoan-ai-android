import SwiftUI

struct VoiceNoteServerSettingsView: View {
    @ObservedObject var store: VoiceNotesStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppConfig
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    init(store: VoiceNotesStore) {
        self.store = store
        _draft = State(initialValue: store.configStore.config)
    }

    var body: some View {
        Form {
            Section("服务器地址") {
                TextField("http://server:19090", text: $draft.voiceNotesURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                LabeledContent("Device-Id", value: draft.deviceID)
            }

            Section("访问 Token") {
                SecureField("VoiceNote Token", text: $draft.voiceNotesToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Token 保存在系统钥匙串中，不会明文写入配置文件。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                        }
                        Text(isTesting ? "正在测试连接…" : "测试服务器和 Token")
                    }
                }
                .disabled(isTesting || !canTestConnection)

                if let testResult, !testResult.isEmpty {
                    Label(
                        testResult,
                        systemImage: testSucceeded
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(testSucceeded ? .green : .red)
                }
            } footer: {
                Text("修改服务器地址或 Token 后，旧服务器的记事和提醒会立即失效，并从新服务器重新读取。")
            }

            Section("默认地址") {
                Button("恢复当前版本默认地址") {
                    draft.voiceNotesURLString = AppConfig.defaultVoiceNotesURL
                    testResult = nil
                }
            } footer: {
                Text(
                    ServerEnvironment.current == .lan
                        ? "内网版默认：http://192.168.0.20:19090"
                        : "域名版默认：http://sql.ms48.com:19090"
                )
            }
        }
        .navigationTitle("VoiceNote 服务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    store.updateConfiguration(draft)
                    dismiss()
                }
                .disabled(normalizedDraft.voiceNotesURL == nil)
            }
        }
        .onAppear {
            draft = store.configStore.config
        }
    }

    private var normalizedDraft: AppConfig {
        var value = draft
        value.normalize()
        return value
    }

    private var canTestConnection: Bool {
        normalizedDraft.voiceNotesURL != nil
            && !normalizedDraft.voiceNotesToken.isEmpty
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let configuration = normalizedDraft

        Task {
            do {
                try await store.testConnection(configuration)
                testSucceeded = true
                testResult = "连接成功，服务器和 Token 可用"
            } catch {
                testSucceeded = false
                testResult = error.localizedDescription
            }
            isTesting = false
        }
    }
}
