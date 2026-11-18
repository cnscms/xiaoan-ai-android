import Foundation
import SwiftUI

struct PrivacyVaultView: View {
    @ObservedObject var vault: PrivacyVaultStore
    let onClearAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSection = 0
    @State private var showClearConfirmation = false
    @State private var actionError: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private let primary = Color(red: 0.16, green: 0.39, blue: 0.91)

    var body: some View {
        NavigationStack {
            Group {
                if vault.isLocked {
                    lockedView
                } else {
                    unlockedView
                }
            }
            .navigationTitle("隐私保险箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !vault.isLocked {
                        Button("锁定") {
                            vault.lock()
                        }
                    }
                }
            }
            .alert("清空隐私保险箱？", isPresented: $showClearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("全部清空", role: .destructive) {
                    clearVault()
                }
            } message: {
                Text("这会删除加密保存的聊天历史和今日待办，无法恢复。")
            }
            .task {
                if vault.isLocked {
                    _ = await vault.unlock()
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active {
                    vault.lock()
                }
            }
            .onDisappear {
                vault.lock()
            }
        }
    }

    private var lockedView: some View {
        ZStack {
            Color(red: 0.969, green: 0.976, blue: 0.992)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.09))
                        .frame(width: 138, height: 138)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.42, blue: 0.95),
                                    Color(red: 0.42, green: 0.27, blue: 0.88)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text("保险箱已锁定")
                    .font(.title2.weight(.bold))

                Text("聊天历史和今日待办使用 AES-GCM\n加密保存在这台设备上")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Button {
                    unlock()
                } label: {
                    HStack(spacing: 8) {
                        if vault.isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "faceid")
                        }
                        Text(
                            vault.isAuthenticating
                                ? "正在验证…"
                                : "使用\(vault.authenticationMethod)解锁"
                        )
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(primary)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vault.isAuthenticating)
                .padding(.horizontal, 28)

                if let error = vault.authenticationError, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Label("密钥保存在系统钥匙串，不离开本机", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 30)
        }
    }

    private var unlockedView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("保险箱已解锁")
                        .font(.subheadline.weight(.semibold))
                    Text("本地加密内容仅在此页面显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.08))

            Picker("内容", selection: $selectedSection) {
                Text("对话").tag(0)
                Text("待办").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List {
                if selectedSection == 0 {
                    messageSection
                } else {
                    noteSection
                }

                if let actionError, !actionError.isEmpty {
                    Section {
                        Text(actionError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("清空隐私保险箱", role: .destructive) {
                        showClearConfirmation = true
                    }
                } footer: {
                    Text("清空会同时删除加密的聊天历史和今日待办。")
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if vault.snapshot.messages.isEmpty {
            Section {
                emptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "还没有加密对话",
                    detail: "和小安聊天后，消息会自动写入保险箱"
                )
            }
        } else {
            Section("历史对话") {
                ForEach(Array(vault.snapshot.messages.reversed())) { message in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(messageTitle(message.role))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    message.role == .assistant
                                        ? primary
                                        : Color.secondary
                                )
                            Spacer()
                            Text(Self.dateFormatter.string(from: message.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        if vault.snapshot.todayItems.isEmpty {
            Section {
                emptyState(
                    icon: "checklist",
                    title: "今天没有待办",
                    detail: "小安生成的今日提醒会加密保存在这里"
                )
            }
        } else {
            Section("今日待办") {
                ForEach(vault.snapshot.todayItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.isReminder ? "⏰" : "📝")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title.isEmpty ? item.content : item.title)
                                .font(.body.weight(.medium))
                            if !item.title.isEmpty && !item.content.isEmpty {
                                Text(item.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(noteTime(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func emptyState(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func messageTitle(_ role: ChatMessage.Role) -> String {
        switch role {
        case .user:
            return "你"
        case .assistant:
            return "小安"
        case .system:
            return "系统"
        }
    }

    private func noteTime(_ item: TodayItem) -> String {
        let seconds = TimeInterval(item.displayTimeMs) / 1_000
        guard seconds > 0 else {
            return item.isReminder ? "待提醒" : "今天"
        }
        return Self.dateFormatter.string(
            from: Date(timeIntervalSince1970: seconds)
        )
    }

    private func unlock() {
        Task {
            _ = await vault.unlock()
        }
    }

    private func clearVault() {
        do {
            try vault.clearAll()
            onClearAll()
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}
