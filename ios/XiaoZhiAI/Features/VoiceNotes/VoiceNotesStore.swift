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
    private var configCancellable: AnyCancellable?
    private var lastConfiguration: AppConfig
    private var configGeneration = 0
    private var activeGeneration: Int?

    init(
        configStore: AppConfigStore,
        client: VoiceNotesClient = VoiceNotesClient()
    ) {
        self.configStore = configStore
        self.client = client
        self.lastConfiguration = configStore.config
        configCancellable = configStore.$config
            .dropFirst()
            .sink { [weak self] config in
                Task { @MainActor [weak self] in
                    self?.handleConfigurationChange(config)
                }
            }
    }

    var hasToken: Bool {
        !configStore.config.voiceNotesToken.isEmpty
    }

    func refresh() async {
        guard hasToken else {
            notes.removeAll()
            reminders.removeAll()
            errorMessage = nil
            return
        }
        if isLoading && activeGeneration == configGeneration {
            return
        }

        let generation = configGeneration
        activeGeneration = generation
        isLoading = true
        errorMessage = nil

        do {
            let config = configStore.config
            async let fetchedNotes = client.fetchNotes(config: config)
            async let fetchedReminders = client.fetchReminders(config: config)
            let resolvedNotes = try await fetchedNotes
            let resolvedReminders = try await fetchedReminders
            guard generation == configGeneration else {
                return
            }
            notes = resolvedNotes
            reminders = resolvedReminders
        } catch {
            if generation == configGeneration {
                errorMessage = error.localizedDescription
            }
        }
        if activeGeneration == generation {
            activeGeneration = nil
            isLoading = false
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

    func updateConfiguration(_ configuration: AppConfig) {
        var value = configuration
        value.normalize()
        configStore.save(value)
    }

    func testConnection(_ configuration: AppConfig) async throws {
        var value = configuration
        value.normalize()
        _ = try await client.fetchNotes(config: value, limit: 1)
    }

    private func handleConfigurationChange(_ configuration: AppConfig) {
        let endpointChanged =
            configuration.voiceNotesURLString
                != lastConfiguration.voiceNotesURLString
            || configuration.voiceNotesToken
                != lastConfiguration.voiceNotesToken
        lastConfiguration = configuration
        guard endpointChanged else {
            return
        }

        configGeneration += 1
        activeGeneration = nil
        isLoading = false
        notes.removeAll()
        reminders.removeAll()
        errorMessage = nil
        Task {
            await refresh()
        }
    }
}
