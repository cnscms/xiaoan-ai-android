import SwiftUI

struct SettingsView: View {
    @ObservedObject var configStore: AppConfigStore
    let onSave: (AppConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppConfig

    init(configStore: AppConfigStore, onSave: @escaping (AppConfig) -> Void) {
        self.configStore = configStore
        self.onSave = onSave
        _draft = State(initialValue: configStore.config)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("设备名称", text: $draft.displayName)
                    TextField("OTA 地址", text: $draft.otaURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("WebSocket 地址", text: $draft.websocketURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Token", text: $draft.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("设备身份") {
                    LabeledContent("Client-Id", value: draft.clientID)
                    LabeledContent("Device-Id", value: draft.deviceID)
                    Text("身份保存在钥匙串中，重启和升级后保持不变。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("恢复当前版本默认地址") {
                        draft.otaURLString = AppConfig.defaultOTAURL
                        draft.websocketURLString = AppConfig.defaultWebSocketURL
                    }
                } footer: {
                    Text(
                        ServerEnvironment.current == .lan
                            ? "内网版默认连接 192.168.0.20:8002 / 8001。"
                            : "域名版默认连接 sql.ms48.com:8002 / 8001。生产环境建议改用 HTTPS/WSS。"
                    )
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var value = draft
                        value.normalize()
                        onSave(value)
                    }
                    .disabled(!normalizedDraft.isComplete)
                }
            }
        }
    }

    private var normalizedDraft: AppConfig {
        var value = draft
        value.normalize()
        return value
    }
}

