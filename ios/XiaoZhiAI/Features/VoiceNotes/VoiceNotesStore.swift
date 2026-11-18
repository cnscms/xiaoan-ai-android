import Combine
import Foundation

@MainActor
final class VoiceNotesStore: ObservableObject {
    @Published private(set) var notes: [VoiceNoteRecord] = []
    @Published private(set) var reminders: [VoiceReminderRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published private(set) var errorMessage: String?

    let configStore: AppConfigStore
    private let client: VoiceNotesClient

    init(
        configStore: AppConfigStore,
        client: VoiceNotesClient = VoiceNotesClient()
    ) {
        self.configStore = configStore
        self.client = client
    }

    var hasToken: Bool {
        !configStore.config.voiceNotesToken.isEmpty
    }

    func refresh() async {
        guard !isLoading else {
            return
        }
        guard hasToken else {
            notes.removeAll()
            reminders.removeAll()
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let config = configStore.config
            async let fetchedNotes = client.fetchNotes(config: config)
            async let fetchedReminders = client.fetchReminders(config: config)
            notes = try await fetchedNotes
            reminders = try await fetchedReminders
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNote(
        content: String,
        title: String
    ) async throws {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        isMutating = true
        defer { isMutating = false }

        do {
            try await client.createNote(
                config: configStore.config,
                content: value,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func createReminder(
        content: String,
        title: String,
        at: Date,
        remindBefore: Int,
        saveNote: Bool
    ) async throws {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        isMutating = true
        defer { isMutating = false }

        do {
            try await client.createReminder(
                config: configStore.config,
                content: value,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                at: at,
                remindBefore: remindBefore,
                saveNote: saveNote
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func cancelReminder(_ reminder: VoiceReminderRecord) async throws {
        isMutating = true
        defer { isMutating = false }

        do {
            try await client.cancelReminder(
                config: configStore.config,
                reminderID: reminder.id
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
