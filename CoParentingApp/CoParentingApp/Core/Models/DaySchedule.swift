import Foundation
import CloudKit

/// Represents a complete schedule for a single day
struct DaySchedule: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var blocks: [TimeBlock]
    var dayNote: String?
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        blocks: [TimeBlock] = [],
        dayNote: String? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.blocks = blocks.sorted { $0.startSlot < $1.startSlot }
        self.dayNote = dayNote
        self.modifiedAt = modifiedAt
    }

    /// Total care hours for this day
    var totalCareHours: Double {
        blocks.filter { $0.provider != .none }.reduce(0) { $0 + $1.durationHours }
    }

    /// Hours by provider for this day
    var hoursByProvider: [CareProvider: Double] {
        var result: [CareProvider: Double] = [:]
        for block in blocks where block.provider != .none {
            result[block.provider, default: 0] += block.durationHours
        }
        return result
    }

    /// Get the provider responsible at a given slot
    func provider(at slot: Int) -> CareProvider {
        blocks.first { $0.contains(slot: slot) }?.provider ?? .none
    }

    /// Check if a time range is available (no existing blocks)
    func isAvailable(startSlot: Int, endSlot: Int) -> Bool {
        !blocks.contains { block in
            block.startSlot < endSlot && block.endSlot > startSlot
        }
    }

    /// Add a new block, merging with adjacent blocks if same provider
    mutating func addBlock(_ block: TimeBlock) {
        // Remove any overlapping blocks
        blocks.removeAll { $0.overlaps(with: block) }

        // Add the new block
        blocks.append(block)

        // Sort by start time
        blocks.sort { $0.startSlot < $1.startSlot }

        modifiedAt = Date()
    }

    /// Remove a block by ID
    mutating func removeBlock(id: UUID) {
        blocks.removeAll { $0.id == id }
        modifiedAt = Date()
    }

    /// Update an existing block
    mutating func updateBlock(_ block: TimeBlock) {
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
            blocks.sort { $0.startSlot < $1.startSlot }
            modifiedAt = Date()
        }
    }
}

// MARK: - CloudKit Integration

extension DaySchedule {
    static let recordType = "DaySchedule"

    enum CloudKitKeys: String {
        case id
        case date
        case dayNote
        case modifiedAt
    }

    init?(from record: CKRecord, blocks: [TimeBlock] = []) {
        guard
            let idString = record[CloudKitKeys.id.rawValue] as? String,
            let id = UUID(uuidString: idString),
            let date = record[CloudKitKeys.date.rawValue] as? Date
        else {
            return nil
        }

        self.id = id
        self.date = date
        self.blocks = blocks
        self.dayNote = record[CloudKitKeys.dayNote.rawValue] as? String
        self.modifiedAt = record[CloudKitKeys.modifiedAt.rawValue] as? Date ?? record.modificationDate ?? Date()
    }

    func toRecord(recordID: CKRecord.ID? = nil) -> CKRecord {
        let record: CKRecord
        if let recordID = recordID {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        } else {
            record = CKRecord(recordType: Self.recordType)
        }

        record[CloudKitKeys.id.rawValue] = id.uuidString
        record[CloudKitKeys.date.rawValue] = date
        record[CloudKitKeys.dayNote.rawValue] = dayNote
        record[CloudKitKeys.modifiedAt.rawValue] = modifiedAt

        return record
    }
}

// MARK: - Sample Data

extension DaySchedule {
    static func sampleSchedule(for date: Date) -> DaySchedule {
        DaySchedule(
            date: date,
            blocks: TimeBlock.sampleBlocks(for: date),
            dayNote: "Regular schedule"
        )
    }
}
