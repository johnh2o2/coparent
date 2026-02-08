import Foundation
import CloudKit

/// Role a user can have in the co-parenting relationship
enum UserRole: String, Codable, CaseIterable {
    case parentA = "parent_a"
    case parentB = "parent_b"
    case caregiver = "caregiver"

    /// Display name using configured provider names when available
    var displayName: String {
        switch self {
        case .parentA: return CareProvider.parentA.displayName
        case .parentB: return CareProvider.parentB.displayName
        case .caregiver: return CareProvider.nanny.displayName
        }
    }
}

/// Represents a user in the co-parenting app
struct User: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var role: UserRole
    var cloudKitRecordID: String?
    var email: String?
    var avatarInitials: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        role: UserRole,
        cloudKitRecordID: String? = nil,
        email: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.cloudKitRecordID = cloudKitRecordID
        self.email = email
        self.avatarInitials = User.initials(from: displayName)
        self.createdAt = createdAt
    }

    /// Generate initials from a display name
    static func initials(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0).uppercased() }
        return initials.prefix(2).joined()
    }

    /// Convert role to CareProvider for schedule display
    var asCareProvider: CareProvider {
        switch role {
        case .parentA: return .parentA
        case .parentB: return .parentB
        case .caregiver: return .nanny
        }
    }
}

// MARK: - CloudKit Integration

extension User {
    static let recordType = "Users"

    enum CloudKitKeys: String {
        case id
        case displayName
        case role
        case email
        case createdAt
    }

    init?(from record: CKRecord) {
        guard
            let idString = record[CloudKitKeys.id.rawValue] as? String,
            let id = UUID(uuidString: idString),
            let displayName = record[CloudKitKeys.displayName.rawValue] as? String,
            let roleRaw = record[CloudKitKeys.role.rawValue] as? String,
            let role = UserRole(rawValue: roleRaw)
        else {
            return nil
        }

        self.id = id
        self.displayName = displayName
        self.role = role
        self.cloudKitRecordID = record.recordID.recordName
        self.email = record[CloudKitKeys.email.rawValue] as? String
        self.avatarInitials = User.initials(from: displayName)
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
        record[CloudKitKeys.displayName.rawValue] = displayName
        record[CloudKitKeys.role.rawValue] = role.rawValue
        record[CloudKitKeys.email.rawValue] = email
        record[CloudKitKeys.createdAt.rawValue] = createdAt

        return record
    }
}

// MARK: - Local Persistence

extension User {
    private static let localIdentityKey = "currentUserIdentity"

    /// Save this user to UserDefaults for instant offline access
    func saveLocally() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.localIdentityKey)
        }
    }

    /// Load the locally persisted user identity
    static func loadLocal() -> User? {
        guard let data = UserDefaults.standard.data(forKey: localIdentityKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    /// Whether a local identity has been set
    static var hasLocalIdentity: Bool {
        UserDefaults.standard.data(forKey: localIdentityKey) != nil
    }
}

// MARK: - Sample Data

extension User {
    static let sampleParentA = User(
        displayName: "Alex Parent",
        role: .parentA,
        email: "alex@example.com"
    )

    static let sampleParentB = User(
        displayName: "Jordan Parent",
        role: .parentB,
        email: "jordan@example.com"
    )

    static let sampleNanny = User(
        displayName: "Sam Caregiver",
        role: .caregiver,
        email: "sam@example.com"
    )
}
