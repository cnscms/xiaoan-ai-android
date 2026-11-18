import Foundation
import SwiftUI

enum VoiceNoteCreateMode: String, Identifiable {
    case note
    case reminder

    var id: String { rawValue }

    var title: String {
        self == .note ? "新建语音记事" : "新建定时提醒"
    }
}

struct VoiceNotesView: View {
    @ObservedObject var store: VoiceNotesStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = 0
    @State private var searchText = ""
    @State private var createMode: VoiceNoteCreateMode?
    @State private var operationError: String?
    @State private var showServerSettings = false

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
                if !store.hasToken {
                    setupView
                } else {
                    content
                }
            }
            .navigationTitle("语音记事本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            createMode = .note
                        } label: {
                            Label("新建记事", systemImage: "note.text.badge.plus")
                        }
                        Button {
                            createMode = .reminder
                        } label: {
                            Label("新建提醒", systemImage: "alarm.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!store.hasToken || store.isMutating)
                    .accessibilityLabel("新建记事或提醒")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showServerSettings = true
                    } label: {
                        Image(systemName: "server.rack")
                    }
                    .accessibilityLabel("配置 VoiceNote 服务器")
                }
            }
            .sheet(item: $createMode) { mode in
                VoiceNoteEditorView(store: store, mode: mode)
            }
            .sheet(isPresented: $showServerSettings) {
                NavigationStack {
                    VoiceNoteServerSettingsView(store: store)
                }
            }
            .task {
                await store.refresh()
            }
            .onChange(of: store.errorMessage) { error in
                if let error, !error.isEmpty {
                    operationError = error
                }
            }
            .alert(
                "语音记事本",
                isPresented: Binding(
                    get: { operationError != nil },
                    set: { if !$0 { operationError = nil } }
                )
            ) {
                Button("知道了") {
                    operationError = nil
                    store.clearError()
                }
            } message: {
                Text(operationError ?? "")
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.09))
                    .frame(width: 128, height: 128)
                Image(systemName: "note.text")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(primary)
            }

            Text("还差一个 VoiceNote Token")
                .font(.title3.weight(.bold))

            Text("完整记事和提醒功能需要连接 VoiceNote 服务。\n地址已默认填好，只需在设置中填写服务 Token。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                showServerSettings = true
            } label: {
                Label("配置 VoiceNote 服务", systemImage: "server.rack")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Label(
                "也可以直接对小安说“帮我记一下…”或“明天下午三点提醒我…”",
                systemImage: "mic.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.06))

            Picker("内容", selection: $selectedSection) {
                Text("记事 \(store.notes.count)").tag(0)
                Text("提醒 \(store.reminders.filter(\.isPending).count)").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List {
                if selectedSection == 0 {
                    notesSection
                } else {
                    remindersSection
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await store.refresh()
            }
            .overlay {
                if store.isLoading && store.notes.isEmpty && store.reminders.isEmpty {
                    ProgressView("正在读取语音记事…")
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索标题或内容")
    }

    @ViewBuilder
    private var notesSection: some View {
        if filteredNotes.isEmpty {
            Section {
                emptyState(
                    icon: "note.text",
                    title: searchText.isEmpty ? "还没有语音记事" : "没有匹配的记事",
                    detail: searchText.isEmpty
                        ? "点右上角加号，或直接对小安说“帮我记一下”"
                        : "换一个关键词试试"
                )
            }
        } else {
            Section("全部记事") {
                ForEach(filteredNotes) { note in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(note.title.isEmpty ? "语音记事" : note.title)
                                .font(.headline)
                            Spacer()
                            if let date = note.createdDate {
                                Text(Self.dateFormatter.string(from: date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(note.transcript)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(5)
                            .textSelection(.enabled)

                        if let duration = note.durationSeconds, duration > 0 {
                            Label(
                                durationText(duration),
                                systemImage: "waveform"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        if filteredReminders.isEmpty {
            Section {
                emptyState(
                    icon: "alarm",
                    title: searchText.isEmpty ? "还没有提醒" : "没有匹配的提醒",
                    detail: searchText.isEmpty
                        ? "点右上角加号，或对小安说“20分钟后提醒我”"
                        : "换一个关键词试试"
                )
            }
        } else {
            Section("提醒列表") {
                ForEach(filteredReminders) { reminder in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: reminderIcon(reminder))
                            .font(.title3)
                            .foregroundStyle(reminderColor(reminder))
                            .frame(width: 26)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(reminder.title.isEmpty ? "提醒" : reminder.title)
                                    .font(.headline)
                                Spacer()
                                Text(statusText(reminder.status))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(reminderColor(reminder))
                            }

                            if !reminder.content.isEmpty {
                                Text(reminder.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }

                            Label(
                                Self.dateFormatter.string(from: reminder.atDate),
                                systemImage: "clock"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if reminder.remindBefore > 0 {
                                Text("提前 \(reminder.remindBefore) 分钟提醒")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if reminder.isPending {
                            Button("取消", role: .destructive) {
                                cancel(reminder)
                            }
                        }
                    }
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
        .padding(.vertical, 30)
    }

    private var filteredNotes: [VoiceNoteRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return store.notes
        }
        return store.notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.transcript.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredReminders: [VoiceReminderRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = query.isEmpty ? store.reminders : store.reminders.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
        return values.sorted {
            if $0.isPending != $1.isPending {
                return $0.isPending
            }
            return $0.atMs < $1.atMs
        }
    }

    private func cancel(_ reminder: VoiceReminderRecord) {
        Task {
            do {
                try await store.cancelReminder(reminder)
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func durationText(_ duration: Double) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "pending":
            return "待提醒"
        case "sent":
            return "已提醒"
        case "cancelled":
            return "已取消"
        default:
            return status
        }
    }

    private func reminderIcon(_ reminder: VoiceReminderRecord) -> String {
        switch reminder.status {
        case "pending":
            return "alarm.fill"
        case "sent":
            return "checkmark.circle.fill"
        case "cancelled":
            return "xmark.circle.fill"
        default:
            return "clock.fill"
        }
    }

    private func reminderColor(_ reminder: VoiceReminderRecord) -> Color {
        switch reminder.status {
        case "pending":
            return primary
        case "sent":
            return .green
        case "cancelled":
            return .secondary
        default:
            return .orange
        }
    }
}

private struct VoiceNoteEditorView: View {
    @ObservedObject var store: VoiceNotesStore
    let mode: VoiceNoteCreateMode

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var reminderDate = Date().addingTimeInterval(3_600)
    @State private var remindBefore = 0
    @State private var saveNote = true
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("可选，留空自动生成", text: $title)
                }

                Section(mode == .note ? "记事内容" : "提醒内容") {
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("例如：下午给客户回电话")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $content)
                            .frame(minHeight: 130)
                    }
                }

                if mode == .reminder {
                    Section("提醒时间") {
                        DatePicker(
                            "什么时候提醒",
                            selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        Stepper(
                            remindBefore == 0
                                ? "不提前"
                                : "提前 \(remindBefore) 分钟",
                            value: $remindBefore,
                            in: 0...1_440,
                            step: 5
                        )
                        Toggle("同时保存为记事", isOn: $saveNote)
                    }
                }

                if let saveError, !saveError.isEmpty {
                    Section {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(
                        isSaving
                            || content.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        if mode == .reminder && reminderDate <= Date() {
            saveError = "提醒时间必须晚于现在"
            return
        }

        isSaving = true
        saveError = nil
        Task {
            do {
                if mode == .note {
                    try await store.createNote(content: value, title: title)
                } else {
                    try await store.createReminder(
                        content: value,
                        title: title,
                        at: reminderDate,
                        remindBefore: remindBefore,
                        saveNote: saveNote
                    )
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
