import Foundation
import CloudKit

/// A single entry in the activity journal — records a schedule change with context.
struct ScheduleChangeEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let userID: UUID
    let userName: String
    let userRole: String          // CareProvider rawValue for color
    let changeDescription: String // Notification message (backwards compat)
    let userNarration: String?    // What the user actually said/typed
    let notificationMessage: String // AI-crafted message for other carers
    let changesApplied: Int       // Number of blocks modified

    // Rich AI-generated metadata (new fields)
    let title: String             // Short AI title for list view
    let purpose: String?          // Context/reason (AI-derived)
    let datesImpacted: String     // Summary of dates affected
    let careTimeDelta: String?    // e.g. "+12.5h to your year"
    let rawAISummary: String?     // Full batch.summary for raw view

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        userID: UUID,
        userName: String,
        userRole: String,
        changeDescription: String,
        userNarration: String? = nil,
        notificationMessage: String,
        changesApplied: Int,
        title: String? = nil,
        purpose: String? = nil,
        datesImpacted: String? = nil,
        careTimeDelta: String? = nil,
        rawAISummary: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.userID = userID
        self.userName = userName
        self.userRole = userRole
        self.changeDescription = changeDescription
        self.userNarration = userNarration
        self.notificationMessage = notificationMessage
        self.changesApplied = changesApplied
        self.title = title ?? "\(userName) updated the schedule"
        self.purpose = purpose
        self.datesImpacted = datesImpacted ?? "Today"
        self.careTimeDelta = careTimeDelta
        self.rawAISummary = rawAISummary
    }

    /// The CareProvider associated with this entry's user role
    var provider: CareProvider {
        CareProvider(rawValue: userRole) ?? .none
    }
}

// MARK: - CloudKit Integration

extension ScheduleChangeEntry {
    static let recordType = "ScheduleChangeEntry"

    enum CloudKitKeys: String {
        case id, timestamp, userID, userName, userRole
        case changeDescription, userNarration, notificationMessage
        case changesApplied
        case title, purpose, datesImpacted, careTimeDelta, rawAISummary
    }

    init?(from record: CKRecord) {
        guard
            let idString = record[CloudKitKeys.id.rawValue] as? String,
            let id = UUID(uuidString: idString),
            let timestamp = record[CloudKitKeys.timestamp.rawValue] as? Date,
            let userIDString = record[CloudKitKeys.userID.rawValue] as? String,
            let userID = UUID(uuidString: userIDString),
            let userName = record[CloudKitKeys.userName.rawValue] as? String,
            let userRole = record[CloudKitKeys.userRole.rawValue] as? String,
            let changeDescription = record[CloudKitKeys.changeDescription.rawValue] as? String,
            let notificationMessage = record[CloudKitKeys.notificationMessage.rawValue] as? String,
            let changesApplied = record[CloudKitKeys.changesApplied.rawValue] as? Int
        else {
            return nil
        }

        self.id = id
        self.timestamp = timestamp
        self.userID = userID
        self.userName = userName
        self.userRole = userRole
        self.changeDescription = changeDescription
        self.userNarration = record[CloudKitKeys.userNarration.rawValue] as? String
        self.notificationMessage = notificationMessage
        self.changesApplied = changesApplied
        self.title = (record[CloudKitKeys.title.rawValue] as? String) ?? "\(userName) updated the schedule"
        self.purpose = record[CloudKitKeys.purpose.rawValue] as? String
        self.datesImpacted = (record[CloudKitKeys.datesImpacted.rawValue] as? String) ?? "Today"
        self.careTimeDelta = record[CloudKitKeys.careTimeDelta.rawValue] as? String
        self.rawAISummary = record[CloudKitKeys.rawAISummary.rawValue] as? String
    }

    func toRecord(recordID: CKRecord.ID? = nil) -> CKRecord {
        let record: CKRecord
        if let recordID = recordID {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        } else {
            record = CKRecord(recordType: Self.recordType)
        }

        record[CloudKitKeys.id.rawValue] = id.uuidString
        record[CloudKitKeys.timestamp.rawValue] = timestamp
        record[CloudKitKeys.userID.rawValue] = userID.uuidString
        record[CloudKitKeys.userName.rawValue] = userName
        record[CloudKitKeys.userRole.rawValue] = userRole
        record[CloudKitKeys.changeDescription.rawValue] = changeDescription
        record[CloudKitKeys.userNarration.rawValue] = userNarration
        record[CloudKitKeys.notificationMessage.rawValue] = notificationMessage
        record[CloudKitKeys.changesApplied.rawValue] = changesApplied
        record[CloudKitKeys.title.rawValue] = title
        record[CloudKitKeys.purpose.rawValue] = purpose
        record[CloudKitKeys.datesImpacted.rawValue] = datesImpacted
        record[CloudKitKeys.careTimeDelta.rawValue] = careTimeDelta
        record[CloudKitKeys.rawAISummary.rawValue] = rawAISummary

        return record
    }
}
