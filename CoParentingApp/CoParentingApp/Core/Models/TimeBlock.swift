import Foundation
import CloudKit

/// Recurrence pattern for a time block
enum RecurrenceType: String, Codable, Equatable {
    case none, everyDay, everyWeek, everyMonth, everyYear
}

/// Represents a continuous block of time assigned to a care provider
/// Uses 15-minute slot system: each day has 96 slots (0-95)
/// Slot 0 = 00:00, Slot 32 = 08:00, Slot 72 = 18:00
struct TimeBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var startSlot: Int // 0-95
    var endSlot: Int   // 0-95
    var provider: CareProvider
    var notes: String?
    var recurrenceType: RecurrenceType
    var recurrenceEndDate: Date?
    var createdAt: Date
    var modifiedAt: Date
    var lastModifiedBy: String?

    init(
        id: UUID = UUID(),
        date: Date,
        startSlot: Int,
        endSlot: Int,
        provider: CareProvider,
        notes: String? = nil,
        recurrenceType: RecurrenceType = .none,
        recurrenceEndDate: Date? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        lastModifiedBy: String? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.startSlot = max(0, min(95, startSlot))
        self.endSlot = max(0, min(96, endSlot))
        self.provider = provider
        self.notes = notes
        self.recurrenceType = recurrenceType
        self.recurrenceEndDate = recurrenceEndDate
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastModifiedBy = lastModifiedBy
    }

    /// Whether this block has a positive duration (endSlot > startSlot)
    var isValid: Bool { endSlot > startSlot }

    /// Duration in minutes
    var durationMinutes: Int {
        (endSlot - startSlot) * 15
    }

    /// Duration in hours (for summary calculations)
    var durationHours: Double {
        Double(durationMinutes) / 60.0
    }

    /// Start time as Date
    var startTime: Date {
        SlotUtility.dateTime(for: startSlot, on: date)
    }

    /// End time as Date
    var endTime: Date {
        SlotUtility.dateTime(for: endSlot, on: date)
    }

    /// Check if this block overlaps with another
    func overlaps(with other: TimeBlock) -> Bool {
        guard Calendar.current.isDate(date, inSameDayAs: other.date) else {
            return false
        }
        return startSlot < other.endSlot && endSlot > other.startSlot
    }

    /// Check if this block contains a given slot
    func contains(slot: Int) -> Bool {
        slot >= startSlot && slot < endSlot
    }

    /// Whether this block falls entirely within the configured care time window
    var isWithinCareWindow: Bool {
        SlotUtility.isWithinCareWindow(start: startSlot, end: endSlot)
    }

    /// Returns a copy clamped to the care window, or nil if entirely outside
    func clampedToCareWindow() -> TimeBlock? {
        guard let clamped = SlotUtility.clampToCareWindow(start: startSlot, end: endSlot) else {
            return nil
        }
        if clamped.start == startSlot && clamped.end == endSlot { return self }
        return TimeBlock(
            id: id,
            date: date,
            startSlot: clamped.start,
            endSlot: clamped.end,
            provider: provider,
            notes: notes,
            recurrenceType: recurrenceType,
            recurrenceEndDate: recurrenceEndDate,
            createdAt: createdAt,
            modifiedAt: Date(),
            lastModifiedBy: lastModifiedBy
        )
    }

    /// Check if this recurring block should appear on the given target date
    func matchesRecurrence(on targetDate: Date) -> Bool {
        guard recurrenceType != .none else { return false }
        let calendar = Calendar.current
        let baseDay = calendar.startOfDay(for: date)
        let target = calendar.startOfDay(for: targetDate)
        guard target >= baseDay else { return false }
        if let endDate = recurrenceEndDate, target > calendar.startOfDay(for: endDate) {
            return false
        }
        switch recurrenceType {
        case .everyDay:
            return true
        case .everyWeek:
            return calendar.component(.weekday, from: baseDay) == calendar.component(.weekday, from: target)
        case .everyMonth:
            return calendar.component(.day, from: baseDay) == calendar.component(.day, from: target)
        case .everyYear:
            return calendar.component(.day, from: baseDay) == calendar.component(.day, from: target) &&
                   calendar.component(.month, from: baseDay) == calendar.component(.month, from: target)
        case .none:
            return false
        }
    }
}

// MARK: - CloudKit Integration

extension TimeBlock {
    static let recordType = "TimeBlock"

    enum CloudKitKeys: String {
        case id
        case date
        case startSlot
        case endSlot
        case provider
        case notes
        case recurrenceType
        case recurrenceEndDate
        case createdAt
        case modifiedAt
        case lastModifiedBy
    }

    init?(from record: CKRecord) {
        guard
            let idString = record[CloudKitKeys.id.rawValue] as? String,
            let id = UUID(uuidString: idString),
            let date = record[CloudKitKeys.date.rawValue] as? Date,
            let startSlot = record[CloudKitKeys.startSlot.rawValue] as? Int,
            let endSlot = record[CloudKitKeys.endSlot.rawValue] as? Int,
            let providerRaw = record[CloudKitKeys.provider.rawValue] as? String,
            let provider = CareProvider(rawValue: providerRaw)
        else {
            return nil
        }

        self.id = id
        self.date = date
        self.startSlot = startSlot
        self.endSlot = endSlot
        self.provider = provider
        self.notes = record[CloudKitKeys.notes.rawValue] as? String
        if let recurrenceRaw = record[CloudKitKeys.recurrenceType.rawValue] as? String,
           let recurrence = RecurrenceType(rawValue: recurrenceRaw) {
            self.recurrenceType = recurrence
        } else {
            self.recurrenceType = .none
        }
        self.recurrenceEndDate = record[CloudKitKeys.recurrenceEndDate.rawValue] as? Date
        self.createdAt = record[CloudKitKeys.createdAt.rawValue] as? Date ?? record.creationDate ?? Date()
        self.modifiedAt = record[CloudKitKeys.modifiedAt.rawValue] as? Date ?? record.modificationDate ?? Date()
        self.lastModifiedBy = record[CloudKitKeys.lastModifiedBy.rawValue] as? String
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
        record[CloudKitKeys.startSlot.rawValue] = startSlot
        record[CloudKitKeys.endSlot.rawValue] = endSlot
        record[CloudKitKeys.provider.rawValue] = provider.rawValue
        record[CloudKitKeys.notes.rawValue] = notes
        record[CloudKitKeys.recurrenceType.rawValue] = recurrenceType.rawValue
        record[CloudKitKeys.recurrenceEndDate.rawValue] = recurrenceEndDate
        record[CloudKitKeys.createdAt.rawValue] = createdAt
        record[CloudKitKeys.modifiedAt.rawValue] = modifiedAt
        record[CloudKitKeys.lastModifiedBy.rawValue] = lastModifiedBy

        return record
    }
}

// MARK: - Sample Data

extension TimeBlock {
    /// Creates sample recurring weekly blocks anchored to the given date.
    /// When `recurring` is true the blocks recur weekly for ~1 year.
    static func sampleBlocks(for date: Date, recurring: Bool = false) -> [TimeBlock] {
        let endDate: Date? = recurring
            ? Calendar.current.date(byAdding: .year, value: 1, to: date)
            : nil
        let recurrence: RecurrenceType = recurring ? .everyWeek : .none

        let windowStart = SlotUtility.careWindowStart
        let windowEnd = SlotUtility.careWindowEnd
        let midpoint = (windowStart + windowEnd) / 2
        let threeQuarter = midpoint + (windowEnd - midpoint) / 2

        return [
            TimeBlock(
                date: date,
                startSlot: windowStart,
                endSlot: midpoint,
                provider: .parentA,
                recurrenceType: recurrence,
                recurrenceEndDate: endDate
            ),
            TimeBlock(
                date: date,
                startSlot: midpoint,
                endSlot: threeQuarter,
                provider: .nanny,
                recurrenceType: recurrence,
                recurrenceEndDate: endDate
            ),
            TimeBlock(
                date: date,
                startSlot: threeQuarter,
                endSlot: windowEnd,
                provider: .parentB,
                recurrenceType: recurrence,
                recurrenceEndDate: endDate
            )
        ]
    }
}
