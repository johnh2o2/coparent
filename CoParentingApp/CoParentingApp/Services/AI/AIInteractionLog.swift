import Foundation

/// A single logged AI interaction (command + result).
struct AIInteraction: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let command: String
    let summary: String
    let changeCount: Int
    let wasApplied: Bool
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        command: String,
        summary: String,
        changeCount: Int,
        wasApplied: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.command = command
        self.summary = summary
        self.changeCount = changeCount
        self.wasApplied = wasApplied
        self.errorMessage = errorMessage
    }
}

/// Persists AI interaction history to UserDefaults.
@Observable
final class AIInteractionLog {
    static let shared = AIInteractionLog()

    private(set) var interactions: [AIInteraction] = []

    private static let storageKey = "ai_interaction_log"

    private init() {
        load()
    }

    /// Log a completed interaction.
    func log(command: String, summary: String, changeCount: Int, wasApplied: Bool, errorMessage: String? = nil) {
        let entry = AIInteraction(
            command: command,
            summary: summary,
            changeCount: changeCount,
            wasApplied: wasApplied,
            errorMessage: errorMessage
        )
        interactions.insert(entry, at: 0)
        save()
    }

    /// Clear all history.
    func clearAll() {
        interactions.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([AIInteraction].self, from: data) {
            interactions = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(interactions) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
