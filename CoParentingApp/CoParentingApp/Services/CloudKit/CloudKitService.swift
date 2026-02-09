import Foundation
import CloudKit

// MARK: - Notifications

extension Notification.Name {
    static let didAcceptCloudKitShare = Notification.Name("didAcceptCloudKitShare")
    static let dashboardShouldReload = Notification.Name("dashboardShouldReload")
}

/// Error types for CloudKit operations
enum CloudKitError: Error, LocalizedError {
    case notAuthenticated
    case networkUnavailable
    case recordNotFound
    case permissionDenied
    case quotaExceeded
    case serverError(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to iCloud to sync your schedule."
        case .networkUnavailable:
            return "Unable to connect. Please check your internet connection."
        case .recordNotFound:
            return "The requested item was not found."
        case .permissionDenied:
            return "You don't have permission to access this data."
        case .quotaExceeded:
            return "iCloud storage is full. Please free up space."
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknown(let error):
            return "An error occurred: \(error.localizedDescription)"
        }
    }
}

/// Service for CloudKit data operations
@Observable
final class CloudKitService {
    static let shared = CloudKitService()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    // Custom zone for atomic operations
    private let customZoneName = "CoParentingZone"
    private var customZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: customZoneName, ownerName: CKCurrentUserDefaultName)
    }

    // State
    var isAuthenticated = false
    var currentUserRecordID: CKRecord.ID?
    var syncStatus: SyncStatus = .idle

    // Expose for diagnostics (test queries against specific zones)
    var privateDB: CKDatabase { privateDatabase }

    // Diagnostics — visible in Settings so TestFlight issues are debuggable
    var containerIdentifier: String { container.containerIdentifier ?? "unknown" }
    var zoneStatus: String = "Unknown"
    var lastOperationLog: String = ""

    enum SyncStatus {
        case idle
        case syncing
        case error(String)
        case synced
    }

    private init() {
        container = CKContainer(identifier: "iCloud.com.johnhoffman.CoParentingAppTwo")
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
    }

    // MARK: - Setup

    /// Initialize CloudKit and check authentication
    func setup() async throws {
        let accountStatus = try await container.accountStatus()

        switch accountStatus {
        case .available:
            // Create the custom zone BEFORE setting isAuthenticated so that
            // views don't start querying CloudKit before the zone exists.
            do {
                try await createCustomZoneIfNeeded()
                print("[CloudKit] Zone ready")
            } catch {
                print("[CloudKit] Zone creation failed (may already exist): \(error.localizedDescription)")
            }
            do {
                currentUserRecordID = try await container.userRecordID()
            } catch {
                print("[CloudKit] Could not fetch user record ID: \(error.localizedDescription)")
            }
            // Set authenticated last — views observe this to decide whether
            // to hit CloudKit, so the zone must exist first.
            isAuthenticated = true
        case .noAccount:
            throw CloudKitError.notAuthenticated
        case .restricted, .couldNotDetermine, .temporarilyUnavailable:
            throw CloudKitError.notAuthenticated
        @unknown default:
            throw CloudKitError.notAuthenticated
        }
    }

    private func createCustomZoneIfNeeded() async throws {
        let zone = CKRecordZone(zoneID: customZoneID)
        do {
            _ = try await privateDatabase.save(zone)
            zoneStatus = "Ready"
        } catch let error as CKError {
            // Various codes can mean "zone already exists" — that's fine.
            switch error.code {
            case .serverRecordChanged, .resultsTruncated:
                zoneStatus = "Ready (exists)"
                break
            default:
                zoneStatus = "FAILED: \(error.code.rawValue) — \(error.localizedDescription)"
                throw error
            }
        }
    }

    /// Diagnostic: verify the custom zone exists by fetching it
    func checkZoneHealth() async -> String {
        do {
            let zones = try await privateDatabase.allRecordZones()
            let zoneNames = zones.map { $0.zoneID.zoneName }
            let hasCustomZone = zoneNames.contains(customZoneName)
            let status = hasCustomZone
                ? "OK — zone '\(customZoneName)' found (\(zones.count) total zones)"
                : "MISSING — zone '\(customZoneName)' not found. Zones: \(zoneNames.joined(separator: ", "))"
            zoneStatus = status
            return status
        } catch {
            let status = "ERROR checking zones: \(error.localizedDescription)"
            zoneStatus = status
            return status
        }
    }

    // MARK: - Generic CRUD Operations

    /// Save a record to CloudKit
    func save(_ record: CKRecord) async throws -> CKRecord {
        syncStatus = .syncing
        print("[CloudKitService] save() called for record type: \(record.recordType), ID: \(record.recordID.recordName)")

        // Ensure record is in custom zone
        let zoneRecord = CKRecord(recordType: record.recordType, recordID: CKRecord.ID(recordName: record.recordID.recordName, zoneID: customZoneID))
        for key in record.allKeys() {
            zoneRecord[key] = record[key]
        }
        print("[CloudKitService] Saving to zone: \(zoneRecord.recordID.zoneID.zoneName)")

        // Use CKModifyRecordsOperation with .allKeys policy to handle both insert and update
        let operation = CKModifyRecordsOperation(recordsToSave: [zoneRecord], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys  // Overwrites server record with local values
        operation.qualityOfService = .userInitiated

        return try await withCheckedThrowingContinuation { continuation in
            var savedRecord: CKRecord?

            operation.perRecordSaveBlock = { _, result in
                if case .success(let record) = result {
                    savedRecord = record
                }
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let record = savedRecord {
                        print("[CloudKitService] Save SUCCESS — record ID: \(record.recordID.recordName)")
                        self.syncStatus = .synced
                        continuation.resume(returning: record)
                    } else {
                        print("[CloudKitService] Save FAILED — no record returned")
                        self.syncStatus = .error("No record returned")
                        continuation.resume(throwing: CloudKitError.unknown(NSError(domain: "CloudKit", code: -1)))
                    }
                case .failure(let error):
                    print("[CloudKitService] Save FAILED — error: \(error)")
                    self.syncStatus = .error(error.localizedDescription)
                    continuation.resume(throwing: self.mapError(error))
                }
            }

            privateDatabase.add(operation)
        }
    }

    /// Fetch a single record by ID
    func fetch(recordID: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await privateDatabase.record(for: recordID)
        } catch {
            throw mapError(error)
        }
    }

    /// Fetch multiple records by type with optional predicate
    func fetchRecords(
        recordType: String,
        predicate: NSPredicate = NSPredicate(value: true),
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil
    ) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = sortDescriptors

        var allRecords: [CKRecord] = []
        var perRecordErrors = 0

        do {
            let (results, _) = try await privateDatabase.records(matching: query, inZoneWith: customZoneID, resultsLimit: limit ?? CKQueryOperation.maximumResults)

            for (_, result) in results {
                switch result {
                case .success(let record):
                    allRecords.append(record)
                case .failure:
                    perRecordErrors += 1
                }
            }

            let log = "fetch \(recordType): \(allRecords.count) records" + (perRecordErrors > 0 ? " (\(perRecordErrors) per-record errors)" : "")
            print("[CloudKitService] \(log)")
            lastOperationLog = log

            return allRecords
        } catch {
            let log = "fetch \(recordType) FAILED: \(error.localizedDescription)"
            print("[CloudKitService] \(log)")
            lastOperationLog = log
            throw mapError(error)
        }
    }

    /// Query using CKQueryOperation directly (diagnostic alternative to convenience API)
    func queryViaOperation(recordType: String, predicate: NSPredicate) async throws -> Int {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        let operation = CKQueryOperation(query: query)
        operation.zoneID = customZoneID
        operation.qualityOfService = .userInitiated

        return try await withCheckedThrowingContinuation { continuation in
            var count = 0

            operation.recordMatchedBlock = { _, result in
                if case .success = result {
                    count += 1
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: count)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            self.privateDatabase.add(operation)
        }
    }

    /// Delete a record
    func delete(recordID: CKRecord.ID) async throws {
        syncStatus = .syncing
        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            syncStatus = .synced
        } catch {
            syncStatus = .error(error.localizedDescription)
            throw mapError(error)
        }
    }

    /// Batch save multiple records
    func batchSave(_ records: [CKRecord]) async throws -> [CKRecord] {
        syncStatus = .syncing
        let totalCount = records.count
        print("[CloudKitService] batchSave() called for \(totalCount) records")

        // Ensure all records are in the custom zone
        let zoneRecords = records.map { record -> CKRecord in
            let zoneRecord = CKRecord(
                recordType: record.recordType,
                recordID: CKRecord.ID(recordName: record.recordID.recordName, zoneID: customZoneID)
            )
            for key in record.allKeys() {
                zoneRecord[key] = record[key]
            }
            return zoneRecord
        }

        let modifyOperation = CKModifyRecordsOperation(recordsToSave: zoneRecords, recordIDsToDelete: nil)
        modifyOperation.savePolicy = .allKeys  // Use allKeys for reliability — matches single save()
        modifyOperation.qualityOfService = .userInitiated

        var savedRecords: [CKRecord] = []
        var perRecordErrors: [String] = []

        return try await withCheckedThrowingContinuation { continuation in
            modifyOperation.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success(let record):
                    savedRecords.append(record)
                case .failure(let error):
                    let msg = "Record \(recordID.recordName): \(error.localizedDescription)"
                    perRecordErrors.append(msg)
                    print("[CloudKitService] perRecordSave FAILED — \(msg)")
                }
            }

            modifyOperation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    let log = "batchSave: \(savedRecords.count)/\(totalCount) saved"
                        + (perRecordErrors.isEmpty ? "" : ", errors: \(perRecordErrors.joined(separator: "; "))")
                    print("[CloudKitService] \(log)")
                    self.lastOperationLog = log

                    if savedRecords.isEmpty && totalCount > 0 {
                        // Operation "succeeded" but every record failed — treat as error
                        let errMsg = "All \(totalCount) records failed: \(perRecordErrors.first ?? "unknown")"
                        self.syncStatus = .error(errMsg)
                        continuation.resume(throwing: CloudKitError.serverError(errMsg))
                    } else {
                        self.syncStatus = .synced
                        continuation.resume(returning: savedRecords)
                    }
                case .failure(let error):
                    let log = "batchSave FAILED: \(error.localizedDescription)"
                    print("[CloudKitService] \(log)")
                    self.lastOperationLog = log
                    self.syncStatus = .error(error.localizedDescription)
                    continuation.resume(throwing: self.mapError(error))
                }
            }

            privateDatabase.add(modifyOperation)
        }
    }

    // MARK: - Sharing

    /// Create a zone-wide share for inviting a co-parent.
    /// This shares ALL records in the custom zone (schedules, messages, etc.).
    func createZoneShare(title: String) async throws -> CKShare {
        syncStatus = .syncing

        let share = CKShare(recordZoneID: customZoneID)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none

        let operation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.qualityOfService = .userInitiated

        return try await withCheckedThrowingContinuation { continuation in
            var savedShare: CKShare?

            operation.perRecordSaveBlock = { _, result in
                if case .success(let record) = result, let s = record as? CKShare {
                    savedShare = s
                }
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let s = savedShare {
                        print("[CloudKitService] Zone share created — URL: \(s.url?.absoluteString ?? "nil")")
                        self.syncStatus = .synced
                        continuation.resume(returning: s)
                    } else {
                        self.syncStatus = .error("No share returned")
                        continuation.resume(throwing: CloudKitError.unknown(NSError(domain: "CloudKit", code: -1)))
                    }
                case .failure(let error):
                    print("[CloudKitService] Zone share FAILED — \(error)")
                    self.syncStatus = .error(error.localizedDescription)
                    continuation.resume(throwing: self.mapError(error))
                }
            }

            privateDatabase.add(operation)
        }
    }

    /// Accept a share invitation
    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await container.accept(metadata)
    }

    /// Fetch shared records
    func fetchSharedRecords(recordType: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))

        var allRecords: [CKRecord] = []

        let zones = try await sharedDatabase.allRecordZones()

        for zone in zones {
            let (results, _) = try await sharedDatabase.records(matching: query, inZoneWith: zone.zoneID)

            for (_, result) in results {
                if case .success(let record) = result {
                    allRecords.append(record)
                }
            }
        }

        return allRecords
    }

    /// Fetch the shared Family record to get provider names and settings
    func fetchSharedFamilySettings() async -> (providerNames: [CareProvider: String], claimedRoles: [UserRole: String])? {
        var providerNames: [CareProvider: String] = [:]
        var claimedRoles: [UserRole: String] = [:]

        do {
            // Fetch shared Family records for provider names
            let familyRecords = try await fetchSharedRecords(recordType: "Family")
            if let family = familyRecords.first {
                if let aName = family["parentAName"] as? String { providerNames[.parentA] = aName }
                if let bName = family["parentBName"] as? String { providerNames[.parentB] = bName }
                if let nName = family["nannyName"] as? String { providerNames[.nanny] = nName }
            }

            // Fetch shared User records to find claimed roles
            let userRecords = try await fetchSharedRecords(recordType: User.recordType)
            for record in userRecords {
                if let user = User(from: record) {
                    claimedRoles[user.role] = user.displayName
                }
            }

            // Also check private User records for claimed roles
            let privateRecords = try await fetchRecords(recordType: User.recordType)
            for record in privateRecords {
                if let user = User(from: record) {
                    claimedRoles[user.role] = user.displayName
                }
            }

            return (providerNames, claimedRoles)
        } catch {
            print("[CloudKit] Failed to fetch shared family settings: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Subscriptions

    /// Set up subscriptions for real-time updates
    func setupSubscriptions() async throws {
        let recordTypes = [TimeBlock.recordType, Message.recordType, MessageThread.recordType]

        for recordType in recordTypes {
            let subscriptionID = "\(recordType)Changes"
            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: NSPredicate(value: true),
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo

            do {
                _ = try await privateDatabase.save(subscription)
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // Subscription might already exist
            } catch let error as CKError where error.code == .unknownItem {
                // Record type doesn't exist yet — subscription will be created when schema exists
                print("[CloudKit] Skipping subscription for \(recordType) — record type not yet in schema")
            }
        }
    }

    // MARK: - Error Mapping

    private func mapError(_ error: Error) -> CloudKitError {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return .notAuthenticated
            case .networkUnavailable, .networkFailure:
                return .networkUnavailable
            case .unknownItem:
                return .recordNotFound
            case .permissionFailure:
                return .permissionDenied
            case .quotaExceeded:
                return .quotaExceeded
            case .serverRejectedRequest:
                return .serverError(ckError.localizedDescription)
            default:
                return .unknown(ckError)
            }
        }
        return .unknown(error)
    }
}
