import Foundation
import CloudKit

/// Repository for ScheduleChangeEntry persistence (CloudKit + local cache).
/// Entries are append-only — no editing or deleting.
@Observable
final class ScheduleChangeRepository {
    static let shared = ScheduleChangeRepository()

    private let cloudKit: CloudKitService
    private(set) var entries: [ScheduleChangeEntry] = []

    private let localCacheKey = "scheduleChangeEntries"

    init(cloudKit: CloudKitService = .shared) {
        self.cloudKit = cloudKit
        loadLocalCache()
    }

    // MARK: - Save

    func save(_ entry: ScheduleChangeEntry) async {
        // Always add to local cache first
        entries.insert(entry, at: 0)
        saveLocalCache()

        // Try to persist to CloudKit if available
        guard cloudKit.isAuthenticated else { return }

        do {
            let record = entry.toRecord()
            _ = try await cloudKit.save(record)
        } catch {
            print("[ScheduleChangeRepository] CloudKit save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch

    func fetchEntries(limit: Int = 50) async -> [ScheduleChangeEntry] {
        guard cloudKit.isAuthenticated else {
            return Array(entries.prefix(limit))
        }

        do {
            // Avoid TRUEPREDICATE — CloudKit Production requires recordName
            // to be Queryable for that. Use a concrete predicate instead.
            let predicate = NSPredicate(format: "timestamp > %@", Date.distantPast as NSDate)
            let sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            let records = try await cloudKit.fetchRecords(
                recordType: ScheduleChangeEntry.recordType,
                predicate: predicate,
                sortDescriptors: sortDescriptors,
                limit: limit
            )

            let fetched = records.compactMap { ScheduleChangeEntry(from: $0) }
            if !fetched.isEmpty {
                entries = fetched
                saveLocalCache()
            }
            return fetched
        } catch {
            print("[ScheduleChangeRepository] CloudKit fetch failed: \(error.localizedDescription)")
            return Array(entries.prefix(limit))
        }
    }

    // MARK: - Local Cache

    private func loadLocalCache() {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey),
              let cached = try? JSONDecoder().decode([ScheduleChangeEntry].self, from: data) else {
            return
        }
        entries = cached
    }

    private func saveLocalCache() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: localCacheKey)
        }
    }
}
