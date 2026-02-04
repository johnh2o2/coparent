import Foundation
import CloudKit

/// Represents a message in a co-parenting thread
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    var threadID: UUID
    var authorID: UUID
    var content: String
    var isAICommand: Bool
    var aiResponse: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        threadID: UUID,
        authorID: UUID,
        content: String,
        isAICommand: Bool = false,
        aiResponse: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.authorID = authorID
        self.content = content
        self.isAICommand = isAICommand
        self.aiResponse = aiResponse
        self.createdAt = createdAt
    }

    /// Check if message content looks like an AI command
    static func detectsAICommand(in text: String) -> Bool {
        let lowercased = text.lowercased()
        let triggers = ["@ai", "hey ai", "can you", "could you", "please change", "move the", "swap", "reschedule"]
        return triggers.contains { lowercased.contains($0) }
    }
}

/// Represents a message thread between co-parents
struct MessageThread: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var participantIDs: [UUID]
    var lastMessageAt: Date?
    var lastMessagePreview: String?
    var unreadCount: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        participantIDs: [UUID],
        lastMessageAt: Date? = nil,
        lastMessagePreview: String? = nil,
        unreadCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.participantIDs = participantIDs
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.unreadCount = unreadCount
        self.createdAt = createdAt
    }
}

// MARK: - CloudKit Integration

extension Message {
    static let recordType = "Message"

    enum CloudKitKeys: String {
        case id
        case threadID
        case authorID
        case content
        case isAICommand
        case aiResponse
        case createdAt
    }

    init?(from record: CKRecord) {
        guard
            let idString = record[CloudKitKeys.id.rawValue] as? String,
            let id = UUID(uuidString: idString),
            let threadIDString = record[CloudKitKeys.threadID.rawValue] as? String,
            let threadID = UUID(uuidString: threadIDString),
            let authorIDString = record[CloudKitKeys.authorID.rawValue] as? String,
            let authorID = UUID(uuidString: authorIDString),
            let content = record[CloudKitKeys.content.rawValue] as? String
        else {
            return nil
        }

        self.id = id
        self.threadID = threadID
        self.authorID = authorID
        self.content = content
        self.isAICommand = record[CloudKitKeys.isAICommand.rawValue] as? Bool ?? false
        self.aiResponse = record[CloudKitKeys.aiResponse.rawValue] as? String
        self.createdAt = record[CloudKitKeys.createdAt.rawValue] as? Date ?? record.creationDate ?? Date()
    }

    func toRecord(recordID: CKRecord.ID? = nil) -> CKRecord {
        let record: CKRecord
        if let recordID = recordID {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        } else {
            record = CKRecord(recordType: Self.recordType)
        }

        record[CloudKitKeys.id.rawValue] = id.uuidString
        record[CloudKitKeys.threadID.rawValue] = threadID.uuidString
        record[CloudKitKeys.authorID.rawValue] = authorID.uuidString
        record[CloudKitKeys.content.rawValue] = content
        record[CloudKitKeys.isAICommand.rawValue] = isAICommand
        record[CloudKitKeys.aiResponse.rawValue] = aiResponse
        record[CloudKitKeys.createdAt.rawValue] = createdAt

        return record
    }
}

extension MessageThread {
    static let recordType = "MessageThread"

    enum CloudKitKeys: String {
        case id
        case title
        case participantIDs
        case lastMessageAt
        case lastMessagePreview
        case unreadCount
        case createdAt
    }

    init?(from record: CKRecord) {
        guard
            let idString = record[CloudKitKeys.id.rawValue] as? String,
            let id = UUID(uuidString: idString),
            let title = record[CloudKitKeys.title.rawValue] as? String,
            let participantIDStrings = record[CloudKitKeys.participantIDs.rawValue] as? [String]
        else {
            return nil
        }

        self.id = id
        self.title = title
        self.participantIDs = participantIDStrings.compactMap { UUID(uuidString: $0) }
        self.lastMessageAt = record[CloudKitKeys.lastMessageAt.rawValue] as? Date
        self.lastMessagePreview = record[CloudKitKeys.lastMessagePreview.rawValue] as? String
        self.unreadCount = record[CloudKitKeys.unreadCount.rawValue] as? Int ?? 0
        self.createdAt = record[CloudKitKeys.createdAt.rawValue] as? Date ?? record.creationDate ?? Date()
    }

    func toRecord(recordID: CKRecord.ID? = nil) -> CKRecord {
        let record: CKRecord
        if let recordID = recordID {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        } else {
            record = CKRecord(recordType: Self.recordType)
        }

        record[CloudKitKeys.id.rawValue] = id.uuidString
        record[CloudKitKeys.title.rawValue] = title
        record[CloudKitKeys.participantIDs.rawValue] = participantIDs.map { $0.uuidString }
        record[CloudKitKeys.lastMessageAt.rawValue] = lastMessageAt
        record[CloudKitKeys.lastMessagePreview.rawValue] = lastMessagePreview
        record[CloudKitKeys.unreadCount.rawValue] = unreadCount
        record[CloudKitKeys.createdAt.rawValue] = createdAt

        return record
    }
}

// MARK: - Sample Data

extension MessageThread {
    static var sampleThread: MessageThread {
        MessageThread(
            title: "Schedule Discussion",
            participantIDs: [User.sampleParentA.id, User.sampleParentB.id],
            lastMessageAt: Date(),
            lastMessagePreview: "Sounds good, let's do that!",
            unreadCount: 2
        )
    }
}

extension Message {
    static func sampleMessages(in thread: MessageThread) -> [Message] {
        let parentA = User.sampleParentA
        let parentB = User.sampleParentB

        return [
            Message(
                threadID: thread.id,
                authorID: parentA.id,
                content: "Can we swap Tuesday and Thursday this week?",
                createdAt: Date().addingTimeInterval(-3600 * 2)
            ),
            Message(
                threadID: thread.id,
                authorID: parentB.id,
                content: "Sure, that works for me!",
                createdAt: Date().addingTimeInterval(-3600)
            ),
            Message(
                threadID: thread.id,
                authorID: parentA.id,
                content: "@ai please swap my Tuesday and Thursday schedules",
                isAICommand: true,
                aiResponse: "I've prepared a swap of Tuesday (Parent A 8am-6pm) with Thursday (Parent B 8am-6pm). Please review and approve.",
                createdAt: Date().addingTimeInterval(-1800)
            )
        ]
    }
}
