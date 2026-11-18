import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var configStore: AppConfigStore
    let onSave: (AppConfig) -> Void
    let onConnect: (AppConfig) -> Void
    let onAbort: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("xiaoan.binding.state") private var bindingState = ""
    @AppStorage("xiaoan.binding.code") private var savedBindingCode = ""
    @State private var draft: AppConfig
    @State private var isBinding = false
    @State private var bindingCode = ""
    @State private var bindingMessage = ""
    @State private var bindingError: String?

    init(
        configStore: AppConfigStore,
        onSave: @escaping (AppConfig) -> Void,
        onConnect: @escaping (AppConfig) -> Void = { _ in },
        onAbort: @escaping () -> Void = {}
    ) {
        self.configStore = configStore
        self.onSave = onSave
        self.onConnect = onConnect
        self.onAbort = onAbort
        _draft = State(initialValue: configStore.config)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器与设备") {
                    TextField("设备名称", text: $draft.displayName)
                    TextField("OTA 地址", text: $draft.otaURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("WebSocket 地址", text: $draft.websocketURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("视觉分析地址", text: $draft.visionURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("VoiceNote 服务地址", text: $draft.voiceNotesURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Token（服务端关闭鉴权时留空）", text: $draft.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("VoiceNote Token", text: $draft.voiceNotesToken)
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

                Section("天气") {
                    TextField("天气城市，例如：眉山", text: $draft.weatherCity)
                    HStack {
                        TextField(
                            "纬度",
                            value: $draft.weatherLatitude,
                            format: .number.precision(.fractionLength(2...6))
                        )
                        .keyboardType(.numbersAndPunctuation)

                        Divider()

                        TextField(
                            "经度",
                            value: $draft.weatherLongitude,
                            format: .number.precision(.fractionLength(2...6))
                        )
                        .keyboardType(.numbersAndPunctuation)
                    }
                    Button("保存天气设置并刷新") {
                        let value = normalizedDraft
                        configStore.save(value)
                        draft = configStore.config
                        onSave(value)
                        dismiss()
                    }
                    .disabled(!normalizedDraft.isComplete)
                }

                Section("设备绑定") {
                    Text(displayBindingCode)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color(red: 0.10, green: 0.32, blue: 0.66))
                        .padding(.vertical, 4)

                    HStack {
                        Button("生成绑定码") {
                            requestBindingCode()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBinding)

                        Spacer()

                        Button("检查绑定") {
                            requestBindingCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBinding)
                    }

                    if isBinding {
                        Label(bindingMessage, systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let bindingError, !bindingError.isEmpty {
                        Text(bindingError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if !bindingMessage.isEmpty {
                        Text(bindingMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("连接控制") {
                    Button("保存并连接") {
                        let value = normalizedDraft
                        onSave(value)
                        onConnect(value)
                        dismiss()
                    }
                    .disabled(!normalizedDraft.isComplete)

                    Button("打断当前回答", role: .destructive) {
                        onAbort()
                    }
                }

                Section {
                    Button("恢复当前版本默认地址") {
                        draft.otaURLString = AppConfig.defaultOTAURL
                        draft.websocketURLString = AppConfig.defaultWebSocketURL
                        draft.visionURLString = AppConfig.defaultVisionURL
                        draft.voiceNotesURLString = AppConfig.defaultVoiceNotesURL
                    }
                } footer: {
                    Text(
                        ServerEnvironment.current == .lan
                            ? "内网版默认使用 192.168.0.20:8002 / 8001 / 8003 / 19090。"
                            : "域名版默认使用 sql.ms48.com:8002 / 8001 / 8003 / 19090。生产环境建议改用 HTTPS/WSS。"
                    )
                }

                Section("版本信息") {
                    LabeledContent("应用", value: ServerEnvironment.current.displayName)
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("构建", value: appBuild)
                    LabeledContent("语音链路", value: "Opus 16 kHz / 60 ms")
                }
            }
            .navigationTitle("服务器与设备设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(normalizedDraft)
                        dismiss()
                    }
                    .disabled(!normalizedDraft.isComplete)
                }
            }
            .onAppear {
                bindingCode = savedBindingCode
                if bindingState == "bound" {
                    bindingMessage = "设备已绑定"
                }
            }
        }
    }

    private var normalizedDraft: AppConfig {
        var value = draft
        value.normalize()
        return value
    }

    private var displayBindingCode: String {
        if !bindingCode.isEmpty {
            return formatBindingCode(bindingCode)
        }
        if bindingState == "bound" {
            return "设备已绑定"
        }
        return "等待验证码"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func requestBindingCode() {
        let value = normalizedDraft
        isBinding = true
        bindingError = nil
        bindingMessage = "正在连接 OTA 服务…"
        configStore.save(value)
        draft = configStore.config

        Task {
            do {
                let response = try await OtaClient().fetch(config: configStore.config)
                var updated = configStore.config
                let websocketURL = response.websocket.url
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !websocketURL.isEmpty {
                    updated.websocketURLString = websocketURL
                }
                if let token = response.websocket.token, !token.isEmpty {
                    updated.token = token
                }
                configStore.save(updated)
                draft = configStore.config

                if let activation = response.activation,
                   !activation.code.isEmpty {
                    bindingCode = activation.code
                    savedBindingCode = activation.code
                    bindingState = "pending"
                    bindingMessage = activation.message.isEmpty
                        ? "等待在小安控制台完成绑定"
                        : activation.message
                } else {
                    bindingCode = ""
                    savedBindingCode = ""
                    bindingState = "bound"
                    bindingMessage = "设备已绑定，连接 Token 已刷新"
                }
            } catch {
                bindingError = error.localizedDescription
                bindingMessage = ""
            }
            isBinding = false
        }
    }

    private func formatBindingCode(_ value: String) -> String {
        guard value.count == 6 else {
            return value
        }
        let index = value.index(value.startIndex, offsetBy: 3)
        return "\(value[..<index]) \(value[index...])"
    }
}
