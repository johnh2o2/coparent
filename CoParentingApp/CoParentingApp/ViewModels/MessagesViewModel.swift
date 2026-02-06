import Foundation
import SwiftUI

/// ViewModel for messaging operations
@Observable
final class MessagesViewModel {
    private let repository: MessageRepository
    private let aiService: AIScheduleService

    // Current user identity (persisted locally, falls back to sample)
    var currentUserID: UUID = User.loadLocal()?.id ?? User.sampleParentA.id

    // State
    var threads: [MessageThread] = []
    var selectedThread: MessageThread?
    var messages: [Message] = []
    var draftMessage = ""

    var isLoading = false
    var errorMessage: String?

    // AI state
    var isProcessingAICommand = false
    var pendingAIResponse: String?

    init(repository: MessageRepository = MessageRepository(), aiService: AIScheduleService = AIScheduleService()) {
        self.repository = repository
        self.aiService = aiService
    }

    // MARK: - Thread Operations

    /// Load all threads
    func loadThreads() async {
        isLoading = true
        errorMessage = nil

        do {
            threads = try await repository.fetchThreads()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Create a new thread
    func createThread(title: String, participantIDs: [UUID]) async -> MessageThread? {
        isLoading = true
        errorMessage = nil

        do {
            let thread = try await repository.createThread(title: title, participantIDs: participantIDs)
            threads.insert(thread, at: 0)
            isLoading = false
            return thread
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    /// Select a thread and load its messages
    func selectThread(_ thread: MessageThread) async {
        selectedThread = thread
        await loadMessages(for: thread.id)

        // Mark as read
        do {
            try await repository.markThreadAsRead(thread.id)
            if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                threads[index].unreadCount = 0
            }
        } catch {
            // Ignore read marking errors
        }
    }

    // MARK: - Message Operations

    /// Load messages for a thread
    func loadMessages(for threadID: UUID) async {
        isLoading = true
        errorMessage = nil

        do {
            messages = try await repository.fetchMessages(for: threadID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Send a message
    func sendMessage() async {
        guard !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let threadID = selectedThread?.id else {
            return
        }

        let content = draftMessage
        draftMessage = ""

        isLoading = true
        errorMessage = nil

        do {
            let message = try await repository.sendMessage(
                threadID: threadID,
                authorID: currentUserID,
                content: content
            )
            messages.append(message)

            // Check if it's an AI command
            if message.isAICommand {
                await processAICommand(message)
            }
        } catch {
            errorMessage = error.localizedDescription
            draftMessage = content // Restore draft on error
        }

        isLoading = false
    }

    /// Process an AI command in a message
    private func processAICommand(_ message: Message) async {
        isProcessingAICommand = true

        do {
            // Get current schedule blocks for context
            let timeBlockRepo = TimeBlockRepository.shared
            let blocks = try await timeBlockRepo.fetchCurrentWeekBlocks()

            // Parse the command (returns a batch)
            let batch = try await aiService.parseScheduleCommand(message.content, currentBlocks: blocks, currentUser: User.loadLocal())

            // Apply the changes to the calendar
            let (toSave, toDelete) = batch.applyAll()

            for block in toDelete {
                try await timeBlockRepo.delete(block)
            }

            // Remove any existing blocks that overlap with the new ones
            // (handles recurring blocks that the AI didn't explicitly clear)
            let validToSave = toSave.filter { $0.isValid }
            if !validToSave.isEmpty {
                try await timeBlockRepo.removeOverlapping(with: validToSave)
                let _ = try await timeBlockRepo.saveAll(validToSave)
            }

            // Build a confirmation summary of what was actually applied
            let addedCount = batch.changes.filter { $0.changeType == .addBlock }.count
            let removedCount = batch.changes.filter { $0.changeType == .removeBlock }.count
            let changedCount = batch.changes.filter { $0.changeType == .changeTime }.count
            let swapCount = batch.changes.filter { $0.changeType == .swap }.count

            var confirmationParts: [String] = []
            if removedCount > 0 { confirmationParts.append("\(removedCount) removed") }
            if addedCount > 0 { confirmationParts.append("\(addedCount) added") }
            if changedCount > 0 { confirmationParts.append("\(changedCount) updated") }
            if swapCount > 0 { confirmationParts.append("\(swapCount) swapped") }
            let confirmationSummary = confirmationParts.joined(separator: ", ")

            // Update message with AI response + confirmation
            var updatedMessage = message
            updatedMessage.aiResponse = batch.summary
                + "\n\n✓ Calendar updated: \(confirmationSummary)."
            let _ = try await repository.updateMessage(updatedMessage)

            // Update local state
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = updatedMessage
            }

            pendingAIResponse = "\(batch.changeCount) change\(batch.changeCount == 1 ? "" : "s") applied: \(batch.summary)"

        } catch {
            // Update message with error
            var updatedMessage = message
            updatedMessage.aiResponse = "I couldn't process that request: \(error.localizedDescription)"
            let _ = try? await repository.updateMessage(updatedMessage)

            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = updatedMessage
            }
        }

        isProcessingAICommand = false
    }

    // MARK: - Helpers

    /// Get display name for a user ID
    func displayName(for userID: UUID) -> String {
        // Check local user first
        if let localUser = User.loadLocal(), localUser.id == userID {
            return localUser.displayName
        }
        // Fallback to sample data
        if userID == User.sampleParentA.id {
            return User.sampleParentA.displayName
        } else if userID == User.sampleParentB.id {
            return User.sampleParentB.displayName
        }
        return "Unknown"
    }

    /// Check if a message is from the current user
    func isOwnMessage(_ message: Message) -> Bool {
        message.authorID == currentUserID
    }

    /// Total unread count across all threads
    var totalUnreadCount: Int {
        threads.reduce(0) { $0 + $1.unreadCount }
    }

    /// Refresh all data
    func refresh() async {
        await loadThreads()
        if let thread = selectedThread {
            await loadMessages(for: thread.id)
        }
    }
}

// MARK: - Preview Support

extension MessagesViewModel {
    static var preview: MessagesViewModel {
        let viewModel = MessagesViewModel()
        viewModel.repository.loadSampleData()
        viewModel.threads = viewModel.repository.threads
        if let thread = viewModel.threads.first {
            viewModel.selectedThread = thread
            viewModel.messages = viewModel.repository.messagesForThread(thread.id)
        }
        return viewModel
    }
}
