import Foundation
import CloudKit

/// Status of a proposed schedule change
enum ScheduleChangeStatus: String, Codable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case expired = "expired"
}

/// Type of schedule change being proposed
enum ScheduleChangeType: String, Codable {
    case changeTime = "change_time"
    case swap = "swap"
    case addBlock = "add_block"
    case removeBlock = "remove_block"
    case reassign = "reassign"
}

/// Represents a proposed change to the schedule
struct ScheduleChange: Identifiable, Codable, Equatable {
    let id: UUID
    var changeType: ScheduleChangeType
    var originalBlock: TimeBlock?
    var proposedBlock: TimeBlock?
    var secondaryOriginalBlock: TimeBlock?  // For swaps
    var secondaryProposedBlock: TimeBlock?  // For swaps
    var status: ScheduleChangeStatus
    var suggestedByAI: Bool
    var aiExplanation: String?
    var requestedByUserID: UUID?
    var reviewedByUserID: UUID?
    var createdAt: Date
    var reviewedAt: Date?

    init(
        id: UUID = UUID(),
        changeType: ScheduleChangeType,
        originalBlock: TimeBlock? = nil,
        proposedBlock: TimeBlock? = nil,
        secondaryOriginalBlock: TimeBlock? = nil,
        secondaryProposedBlock: TimeBlock? = nil,
        status: ScheduleChangeStatus = .pending,
        suggestedByAI: Bool = false,
        aiExplanation: String? = nil,
        requestedByUserID: UUID? = nil,
        reviewedByUserID: UUID? = nil,
        createdAt: Date = Date(),
        reviewedAt: Date? = nil
    ) {
        self.id = id
        self.changeType = changeType
        self.originalBlock = originalBlock
        self.proposedBlock = proposedBlock
        self.secondaryOriginalBlock = secondaryOriginalBlock
        self.secondaryProposedBlock = secondaryProposedBlock
        self.status = status
        self.suggestedByAI = suggestedByAI
        self.aiExplanation = aiExplanation
        self.requestedByUserID = requestedByUserID
        self.reviewedByUserID = reviewedByUserID
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
    }

    /// Human-readable description of the change
    var description: String {
        switch changeType {
        case .changeTime:
            guard let original = originalBlock, let proposed = proposedBlock else {
                return "Change time"
            }
            return "Move \(original.provider.displayName)'s block from \(SlotUtility.formatSlotRange(start: original.startSlot, end: original.endSlot)) to \(SlotUtility.formatSlotRange(start: proposed.startSlot, end: proposed.endSlot))"

        case .swap:
            guard let first = originalBlock, let second = secondaryOriginalBlock else {
                return "Swap schedules"
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return "Swap \(formatter.string(from: first.date)) (\(first.provider.displayName)) with \(formatter.string(from: second.date)) (\(second.provider.displayName))"

        case .addBlock:
            guard let proposed = proposedBlock else {
                return "Add new block"
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return "Add \(proposed.provider.displayName) on \(formatter.string(from: proposed.date)) from \(SlotUtility.formatSlotRange(start: proposed.startSlot, end: proposed.endSlot))"

        case .removeBlock:
            guard let original = originalBlock else {
                return "Remove block"
            }
            return "Remove \(original.provider.displayName)'s block at \(SlotUtility.formatSlotRange(start: original.startSlot, end: original.endSlot))"

        case .reassign:
            guard let original = originalBlock, let proposed = proposedBlock else {
                return "Reassign block"
            }
            return "Reassign from \(original.provider.displayName) to \(proposed.provider.displayName)"
        }
    }

    /// Apply this change (returns modified blocks)
    func apply() -> [TimeBlock] {
        var result: [TimeBlock] = []

        switch changeType {
        case .changeTime, .reassign:
            if let proposed = proposedBlock {
                result.append(proposed)
            }

        case .swap:
            if let proposed = proposedBlock {
                result.append(proposed)
            }
            if let secondaryProposed = secondaryProposedBlock {
                result.append(secondaryProposed)
            }

        case .addBlock:
            if let proposed = proposedBlock {
                result.append(proposed)
            }

        case .removeBlock:
            // Returns empty - the original block should be deleted
            break
        }

        return result
    }
}

// MARK: - CloudKit Integration

extension ScheduleChange {
    static let recordType = "ScheduleChange"

    enum CloudKitKeys: String {
        case id
        case changeType
        case status
        case suggestedByAI
        case aiExplanation
        case requestedByUserID
        case reviewedByUserID
        case createdAt
        case reviewedAt
        // Block references stored separately
    }

    func toRecord(recordID: CKRecord.ID? = nil) -> CKRecord {
        let record: CKRecord
        if let recordID = recordID {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        } else {
            record = CKRecord(recordType: Self.recordType)
        }

        record[CloudKitKeys.id.rawValue] = id.uuidString
        record[CloudKitKeys.changeType.rawValue] = changeType.rawValue
        record[CloudKitKeys.status.rawValue] = status.rawValue
        record[CloudKitKeys.suggestedByAI.rawValue] = suggestedByAI
        record[CloudKitKeys.aiExplanation.rawValue] = aiExplanation
        record[CloudKitKeys.requestedByUserID.rawValue] = requestedByUserID?.uuidString
        record[CloudKitKeys.reviewedByUserID.rawValue] = reviewedByUserID?.uuidString
        record[CloudKitKeys.createdAt.rawValue] = createdAt
        record[CloudKitKeys.reviewedAt.rawValue] = reviewedAt

        return record
    }
}

// MARK: - Sample Data

extension ScheduleChange {
    static var sampleTimeChange: ScheduleChange {
        let today = Date()
        let originalBlock = TimeBlock(
            date: today,
            startSlot: 32,  // 8:00 AM
            endSlot: 48,    // 12:00 PM
            provider: .parentA
        )
        let proposedBlock = TimeBlock(
            date: today,
            startSlot: 33,  // 8:15 AM
            endSlot: 49,    // 12:15 PM
            provider: .parentA
        )

        return ScheduleChange(
            changeType: .changeTime,
            originalBlock: originalBlock,
            proposedBlock: proposedBlock,
            suggestedByAI: true,
            aiExplanation: "Adjusted pickup time from 8:00 AM to 8:15 AM as requested."
        )
    }

    static var sampleSwap: ScheduleChange {
        let calendar = Calendar.current
        let tuesday = calendar.date(byAdding: .day, value: 2, to: Date())!
        let thursday = calendar.date(byAdding: .day, value: 4, to: Date())!

        let tuesdayBlock = TimeBlock(
            date: tuesday,
            startSlot: 32,
            endSlot: 72,
            provider: .parentA
        )
        let thursdayBlock = TimeBlock(
            date: thursday,
            startSlot: 32,
            endSlot: 72,
            provider: .parentB
        )

        return ScheduleChange(
            changeType: .swap,
            originalBlock: tuesdayBlock,
            proposedBlock: TimeBlock(
                date: tuesday,
                startSlot: 32,
                endSlot: 72,
                provider: .parentB
            ),
            secondaryOriginalBlock: thursdayBlock,
            secondaryProposedBlock: TimeBlock(
                date: thursday,
                startSlot: 32,
                endSlot: 72,
                provider: .parentA
            ),
            suggestedByAI: true,
            aiExplanation: "Swapping Tuesday and Thursday schedules as requested."
        )
    }
}
