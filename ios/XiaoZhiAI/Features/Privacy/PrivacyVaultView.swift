import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct PrivacyVaultView: View {
    @ObservedObject var vault: PrivacyVaultStore
    let onClearAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSection = 0
    @State private var showClearConfirmation = false
    @State private var actionError: String?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImportingPhotos = false
    @State private var previewPhoto: VaultPhoto?
    @State private var photoPendingDeletion: VaultPhoto?

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
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vault.isLocked {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 20,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Image(systemName: "photo.badge.plus")
                        }
                        .accessibilityLabel("从相册添加加密照片")
                    }
                }
            }
            .alert("清空隐私保险箱？", isPresented: $showClearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("全部清空", role: .destructive) {
                    clearVault()
                }
            } message: {
                Text("这会删除加密保存的聊天历史、今日待办和照片，无法恢复。")
            }
            .confirmationDialog(
                "移除这张照片？",
                isPresented: Binding(
                    get: { photoPendingDeletion != nil },
                    set: { if !$0 { photoPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("移除照片", role: .destructive) {
                    if let photo = photoPendingDeletion {
                        deletePhoto(photo)
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .fullScreenCover(item: $previewPhoto) { photo in
                VaultPhotoPreview(vault: vault, photo: photo)
            }
            .task {
                if vault.isLocked {
                    _ = await vault.unlock()
                }
            }
            .onChange(of: selectedPhotoItems) { items in
                guard !items.isEmpty else {
                    return
                }
                importPhotos(items)
            }
            .onChange(of: vault.isLocked) { locked in
                if locked {
                    previewPhoto = nil
                    selectedPhotoItems.removeAll()
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
                Text("照片").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List {
                if selectedSection == 0 {
                    messageSection
                } else if selectedSection == 1 {
                    noteSection
                } else {
                    photoSection
                }

                if isImportingPhotos {
                    Section {
                        Label("正在加密导入照片…", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
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
                    Text("清空会同时删除加密的聊天历史、今日待办和照片。")
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

    @ViewBuilder
    private var photoSection: some View {
        if vault.snapshot.photos.isEmpty {
            Section {
                emptyState(
                    icon: "photo.on.rectangle.angled",
                    title: "还没有加密照片",
                    detail: "点右上角照片按钮，从系统相册选择图片"
                )
            }
        } else {
            Section {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(vault.snapshot.photos.sorted {
                        $0.addedAt > $1.addedAt
                    }) { photo in
                        VaultPhotoCell(
                            vault: vault,
                            photo: photo,
                            onOpen: {
                                previewPhoto = photo
                            },
                            onDelete: {
                                photoPendingDeletion = photo
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("加密照片 · \(vault.snapshot.photos.count) 张")
            } footer: {
                Text("每张照片单独使用 AES-GCM 加密，仅在保险箱解锁时显示。")
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

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !isImportingPhotos else {
            return
        }
        isImportingPhotos = true
        actionError = nil
        selectedSection = 2

        Task {
            var imported = 0
            var failed = 0

            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        failed += 1
                        continue
                    }
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try VaultPhotoProcessor.prepare(data)
                    }.value
                    try vault.importPhoto(
                        data: prepared.data,
                        width: prepared.width,
                        height: prepared.height
                    )
                    imported += 1
                } catch {
                    failed += 1
                }
            }

            selectedPhotoItems.removeAll()
            isImportingPhotos = false
            if failed > 0 {
                actionError = imported > 0
                    ? "已加密导入 \(imported) 张，\(failed) 张失败"
                    : "照片导入失败，请重试"
            }
        }
    }

    private func deletePhoto(_ photo: VaultPhoto) {
        do {
            try vault.deletePhoto(photo)
            actionError = nil
        } catch {
            actionError = "删除照片失败：\(error.localizedDescription)"
        }
        photoPendingDeletion = nil
    }
}

private struct VaultPhotoCell: View {
    @ObservedObject var vault: PrivacyVaultStore
    let photo: VaultPhoto
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.10))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.10))
                }
            }
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                if image != nil {
                    onOpen()
                }
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(.black.opacity(0.58))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(5)
            .accessibilityLabel("移除照片")
        }
        .task(id: photo.id) {
            loadPhoto()
        }
    }

    private func loadPhoto() {
        do {
            guard let data = try vault.decryptedPhotoData(for: photo) else {
                failed = true
                return
            }
            image = UIImage(data: data)
            failed = image == nil
        } catch {
            failed = true
        }
    }
}

private struct VaultPhotoPreview: View {
    @ObservedObject var vault: PrivacyVaultStore
    let photo: VaultPhoto

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.58))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("关闭照片")
                }
                .padding(14)
                Spacer()
            }
        }
        .task(id: photo.id) {
            do {
                if let data = try vault.decryptedPhotoData(for: photo) {
                    image = UIImage(data: data)
                }
            } catch {
                image = nil
            }
        }
    }
}
