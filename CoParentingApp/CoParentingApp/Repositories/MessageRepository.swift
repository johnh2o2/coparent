import Foundation
import CloudKit

/// Repository for Message and MessageThread data operations
@Observable
final class MessageRepository {
    private let cloudKit: CloudKitService

    // Local cache
    private(set) var threads: [MessageThread] = []
    private(set) var messages: [UUID: [Message]] = [:] // threadID -> messages
    private var threadRecordIDMapping: [UUID: CKRecord.ID] = [:]
    private var messageRecordIDMapping: [UUID: CKRecord.ID] = [:]

    var isLoading = false
    var error: Error?

    init(cloudKit: CloudKitService = .shared) {
        self.cloudKit = cloudKit
    }

    // MARK: - Thread Operations

    /// Fetch all message threads
    func fetchThreads() async throws -> [MessageThread] {
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard cloudKit.isAuthenticated else {
            print("[MessageRepository] fetchThreads() — CloudKit not authenticated, returning local cache (\(threads.count) threads)")
            return threads
        }
        print("[MessageRepository] fetchThreads() — CloudKit authenticated, fetching from CloudKit")

        let sortDescriptors = [
            NSSortDescriptor(key: "lastMessageAt", ascending: false)
        ]

        do {
            let records = try await cloudKit.fetchRecords(
                recordType: MessageThread.recordType,
                sortDescriptors: sortDescriptors
            )

            let fetchedThreads = records.compactMap { record -> MessageThread? in
                guard let thread = MessageThread(from: record) else { return nil }
                threadRecordIDMapping[thread.id] = record.recordID
                return thread
            }

            self.threads = fetchedThreads
            return fetchedThreads
        } catch {
            self.error = error
            throw error
        }
    }

    /// Create a new thread
    func createThread(title: String, participantIDs: [UUID]) async throws -> MessageThread {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let thread = MessageThread(title: title, participantIDs: participantIDs)

        guard cloudKit.isAuthenticated else {
            threads.insert(thread, at: 0)
            return thread
        }

        do {
            let record = thread.toRecord()
            let savedRecord = try await cloudKit.save(record)

            if let savedThread = MessageThread(from: savedRecord) {
                threadRecordIDMapping[savedThread.id] = savedRecord.recordID
                threads.insert(savedThread, at: 0)
                return savedThread
            }

            return thread
        } catch {
            self.error = error
            throw error
        }
    }

    /// Update a thread (e.g., when new message arrives)
    func updateThread(_ thread: MessageThread) async throws -> MessageThread {
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard cloudKit.isAuthenticated else {
            if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                threads[index] = thread
            }
            return thread
        }

        do {
            let record = thread.toRecord(recordID: threadRecordIDMapping[thread.id])
            let savedRecord = try await cloudKit.save(record)

            if let savedThread = MessageThread(from: savedRecord) {
                threadRecordIDMapping[savedThread.id] = savedRecord.recordID

                if let index = threads.firstIndex(where: { $0.id == savedThread.id }) {
                    threads[index] = savedThread
                }

                return savedThread
            }

            return thread
        } catch {
            self.error = error
            throw error
        }
    }

    // MARK: - Message Operations

    /// Fetch messages for a thread
    func fetchMessages(for threadID: UUID) async throws -> [Message] {
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard cloudKit.isAuthenticated else {
            print("[MessageRepository] fetchMessages() — CloudKit not authenticated, returning local cache")
            return messages[threadID] ?? []
        }
        print("[MessageRepository] fetchMessages() — CloudKit authenticated, fetching from CloudKit")

        let predicate = NSPredicate(format: "threadID == %@", threadID.uuidString)
        let sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]

        do {
            let records = try await cloudKit.fetchRecords(
                recordType: Message.recordType,
                predicate: predicate,
                sortDescriptors: sortDescriptors
            )

            let fetchedMessages = records.compactMap { record -> Message? in
                guard let message = Message(from: record) else { return nil }
                messageRecordIDMapping[message.id] = record.recordID
                return message
            }

            messages[threadID] = fetchedMessages
            return fetchedMessages
        } catch {
            self.error = error
            throw error
        }
    }

    /// Send a new message
    func sendMessage(threadID: UUID, authorID: UUID, content: String) async throws -> Message {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let isAICommand = Message.detectsAICommand(in: content)
        let message = Message(
            threadID: threadID,
            authorID: authorID,
            content: content,
            isAICommand: isAICommand
        )

        guard cloudKit.isAuthenticated else {
            // Local-only mode
            if messages[threadID] != nil {
                messages[threadID]?.append(message)
            } else {
                messages[threadID] = [message]
            }

            if var thread = threads.first(where: { $0.id == threadID }) {
                thread.lastMessageAt = message.createdAt
                thread.lastMessagePreview = content.truncated(to: 50)
                if let index = threads.firstIndex(where: { $0.id == threadID }) {
                    threads[index] = thread
                }
            }

            return message
        }

        do {
            let record = message.toRecord()
            let savedRecord = try await cloudKit.save(record)

            if let savedMessage = Message(from: savedRecord) {
                messageRecordIDMapping[savedMessage.id] = savedRecord.recordID

                // Update local cache
                if messages[threadID] != nil {
                    messages[threadID]?.append(savedMessage)
                } else {
                    messages[threadID] = [savedMessage]
                }

                // Update thread's last message
                if var thread = threads.first(where: { $0.id == threadID }) {
                    thread.lastMessageAt = savedMessage.createdAt
                    thread.lastMessagePreview = content.truncated(to: 50)
                    _ = try? await updateThread(thread)
                }

                return savedMessage
            }

            return message
        } catch {
            self.error = error
            throw error
        }
    }

    /// Update a message (e.g., to add AI response)
    func updateMessage(_ message: Message) async throws -> Message {
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard cloudKit.isAuthenticated else {
            if let index = messages[message.threadID]?.firstIndex(where: { $0.id == message.id }) {
                messages[message.threadID]?[index] = message
            }
            return message
        }

        do {
            let record = message.toRecord(recordID: messageRecordIDMapping[message.id])
            let savedRecord = try await cloudKit.save(record)

            if let savedMessage = Message(from: savedRecord) {
                messageRecordIDMapping[savedMessage.id] = savedRecord.recordID

                // Update cache
                if let index = messages[message.threadID]?.firstIndex(where: { $0.id == savedMessage.id }) {
                    messages[message.threadID]?[index] = savedMessage
                }

                return savedMessage
            }

            return message
        } catch {
            self.error = error
            throw error
        }
    }

    // MARK: - Local Operations

    /// Get messages for a thread from cache
    func messagesForThread(_ threadID: UUID) -> [Message] {
        messages[threadID] ?? []
    }

    /// Mark thread as read
    func markThreadAsRead(_ threadID: UUID) async throws {
        guard var thread = threads.first(where: { $0.id == threadID }), thread.unreadCount > 0 else {
            return
        }

        thread.unreadCount = 0
        _ = try await updateThread(thread)
    }

    /// Clear local cache
    func clearCache() {
        threads.removeAll()
        messages.removeAll()
        threadRecordIDMapping.removeAll()
        messageRecordIDMapping.removeAll()
    }
}

// MARK: - Sample Data Support

extension MessageRepository {
    /// Load sample data for preview/testing
    func loadSampleData() {
        let thread = MessageThread.sampleThread
        threads = [thread]
        messages[thread.id] = Message.sampleMessages(in: thread)
    }
}
