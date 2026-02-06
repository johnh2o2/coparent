import Foundation
import CloudKit

// MARK: - Notifications

extension Notification.Name {
    static let didAcceptCloudKitShare = Notification.Name("didAcceptCloudKitShare")
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
            isAuthenticated = true
            // Zone creation is best-effort — the zone may already exist
            // and various CKError codes can signal that.
            do {
                try await createCustomZoneIfNeeded()
            } catch {
                print("[CloudKit] Zone creation failed (may already exist): \(error.localizedDescription)")
            }
            do {
                currentUserRecordID = try await container.userRecordID()
            } catch {
                print("[CloudKit] Could not fetch user record ID: \(error.localizedDescription)")
            }
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
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Zone already exists, which is fine
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

        do {
            let (results, _) = try await privateDatabase.records(matching: query, inZoneWith: customZoneID, resultsLimit: limit ?? CKQueryOperation.maximumResults)

            for (_, result) in results {
                if case .success(let record) = result {
                    allRecords.append(record)
                }
            }

            return allRecords
        } catch {
            throw mapError(error)
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
        print("[CloudKitService] batchSave() called for \(records.count) records")

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

        do {
            let modifyOperation = CKModifyRecordsOperation(recordsToSave: zoneRecords, recordIDsToDelete: nil)
            modifyOperation.savePolicy = .changedKeys
            modifyOperation.qualityOfService = .userInitiated

            var savedRecords: [CKRecord] = []

            return try await withCheckedThrowingContinuation { continuation in
                modifyOperation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        print("[CloudKitService] batchSave SUCCESS — saved \(savedRecords.count) records")
                        self.syncStatus = .synced
                        continuation.resume(returning: savedRecords)
                    case .failure(let error):
                        print("[CloudKitService] batchSave FAILED — error: \(error)")
                        self.syncStatus = .error(error.localizedDescription)
                        continuation.resume(throwing: self.mapError(error))
                    }
                }

                modifyOperation.perRecordSaveBlock = { _, result in
                    switch result {
                    case .success(let record):
                        savedRecords.append(record)
                    case .failure(let error):
                        print("[CloudKitService] perRecordSave FAILED — error: \(error)")
                    }
                }

                privateDatabase.add(modifyOperation)
            }
        }
    }

    // MARK: - Sharing

    /// Create a share for inviting a co-parent
    func createShare(for rootRecord: CKRecord, title: String) async throws -> CKShare {
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none

        let _ = try await batchSave([rootRecord, share])

        return share
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
