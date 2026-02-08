import Foundation
import CloudKit

/// Errors specific to time block persistence
enum TimeBlockError: Error, LocalizedError {
    case outsideCareWindow

    var errorDescription: String? {
        switch self {
        case .outsideCareWindow:
            return "The time block falls entirely outside the care time window."
        }
    }
}

/// Repository for TimeBlock data operations
@Observable
final class TimeBlockRepository {
    /// Shared instance so all view models operate on the same data.
    static let shared = TimeBlockRepository()

    private let cloudKit: CloudKitService

    // Local cache
    private(set) var timeBlocks: [TimeBlock] = []
    private var recordIDMapping: [UUID: CKRecord.ID] = [:]

    var isLoading = false
    var error: Error?

    /// Tracks consecutive CloudKit fetch failures. Resets to 0 on success.
    /// A high count (e.g. > 3) suggests a persistent issue like missing
    /// queryable indexes rather than a transient network hiccup.
    private(set) var consecutiveFetchFailures = 0
    /// The last CloudKit fetch error, if any. Nil when fetches succeed.
    private(set) var lastFetchError: Error?

    init(cloudKit: CloudKitService = .shared) {
        self.cloudKit = cloudKit
    }

    // MARK: - Fetch Operations

    /// Fetch all time blocks for a date range
    func fetchBlocks(from startDate: Date, to endDate: Date) async throws -> [TimeBlock] {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // If CloudKit is not available, return from local cache (no sample data)
        guard cloudKit.isAuthenticated else {
            print("[TimeBlockRepository] fetchBlocks() — CloudKit not authenticated, returning local cache (\(timeBlocks.count) blocks)")
            let rangeStart = Calendar.current.startOfDay(for: startDate)
            let rangeEnd = Calendar.current.startOfDay(for: endDate)
            return timeBlocks.filter { block in
                if block.recurrenceType != .none {
                    // Include recurring blocks whose base date <= range end
                    // and whose recurrence hasn't ended before range start
                    return block.date <= rangeEnd &&
                        (block.recurrenceEndDate == nil || block.recurrenceEndDate! >= rangeStart)
                }
                // Non-recurring: standard date range check
                return block.date >= rangeStart && block.date <= rangeEnd
            }
        }
        print("[TimeBlockRepository] fetchBlocks() — CloudKit authenticated, fetching from CloudKit")

        // CloudKit doesn't support OR compound predicates, so run two queries and merge.
        let dateRangePredicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        let recurringPredicate = NSPredicate(
            format: "recurrenceType != %@ AND date <= %@",
            RecurrenceType.none.rawValue,
            endDate as NSDate
        )

        let sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: true),
            NSSortDescriptor(key: "startSlot", ascending: true)
        ]

        do {
            async let dateRangeRecords = cloudKit.fetchRecords(
                recordType: TimeBlock.recordType,
                predicate: dateRangePredicate,
                sortDescriptors: sortDescriptors
            )
            async let recurringRecords = cloudKit.fetchRecords(
                recordType: TimeBlock.recordType,
                predicate: recurringPredicate,
                sortDescriptors: sortDescriptors
            )

            // Merge and deduplicate by record ID
            var seen = Set<String>()
            var allRecords: [CKRecord] = []
            for record in try await dateRangeRecords + recurringRecords {
                let id = record.recordID.recordName
                if seen.insert(id).inserted {
                    allRecords.append(record)
                }
            }

            let blocks = allRecords.compactMap { record -> TimeBlock? in
                guard let block = TimeBlock(from: record) else { return nil }
                recordIDMapping[block.id] = record.recordID
                return block
            }

            // Update cache
            self.timeBlocks = mergeBlocks(existing: timeBlocks, fetched: blocks)

            // CloudKit query succeeded — clear failure tracking
            consecutiveFetchFailures = 0
            lastFetchError = nil

            return blocks
        } catch {
            // Track consecutive failures to distinguish transient (network)
            // from persistent (missing indexes, schema not deployed) issues.
            consecutiveFetchFailures += 1
            lastFetchError = error

            let ckDetail: String
            if let ckError = error as? CloudKitError {
                ckDetail = "CloudKitError.\(ckError)"
            } else {
                ckDetail = "\(error)"
            }
            print("[TimeBlockRepository] CloudKit fetch FAILED (\(consecutiveFetchFailures) consecutive). Error: \(ckDetail)")

            if consecutiveFetchFailures >= 3 {
                print("[TimeBlockRepository] ⚠️ PERSISTENT FAILURE — CloudKit queries have failed \(consecutiveFetchFailures) times in a row.")
                print("[TimeBlockRepository] This likely means the CloudKit schema is missing queryable indexes.")
                print("[TimeBlockRepository] Go to https://icloud.developer.apple.com → select your container → Schema → Indexes")
                print("[TimeBlockRepository] Ensure 'date', 'recurrenceType', 'startSlot' on TimeBlock are marked Queryable + Sortable.")
            }

            // Fall back to local cache so the UI isn't empty, but the
            // failure state is tracked and can be surfaced by the UI.
            let rangeStart = Calendar.current.startOfDay(for: startDate)
            let rangeEnd = Calendar.current.startOfDay(for: endDate)
            return timeBlocks.filter { block in
                if block.recurrenceType != .none {
                    return block.date <= rangeEnd &&
                        (block.recurrenceEndDate == nil || block.recurrenceEndDate! >= rangeStart)
                }
                return block.date >= rangeStart && block.date <= rangeEnd
            }
        }
    }

    /// Fetch blocks for a specific date
    func fetchBlocks(for date: Date) async throws -> [TimeBlock] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await fetchBlocks(from: startOfDay, to: endOfDay)
    }

    /// Fetch blocks for the current week
    func fetchCurrentWeekBlocks() async throws -> [TimeBlock] {
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return []
        }

        return try await fetchBlocks(from: weekStart, to: weekEnd)
    }

    // MARK: - Save Operations

    /// Save a new time block (clamped to the care time window)
    func save(_ block: TimeBlock) async throws -> TimeBlock {
        var stamped = block
        stamped.lastModifiedBy = User.loadLocal()?.asCareProvider.rawValue
        guard let clamped = stamped.clampedToCareWindow() else {
            throw TimeBlockError.outsideCareWindow
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        // Local-only mode when CloudKit unavailable
        guard cloudKit.isAuthenticated else {
            print("[TimeBlockRepository] save() — CloudKit not authenticated, using local storage")
            if let index = timeBlocks.firstIndex(where: { $0.id == clamped.id }) {
                timeBlocks[index] = clamped
            } else {
                timeBlocks.append(clamped)
                timeBlocks.sort { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
            }
            return clamped
        }
        print("[TimeBlockRepository] save() — CloudKit authenticated, saving to CloudKit")

        do {
            let record = clamped.toRecord(recordID: recordIDMapping[clamped.id])
            let savedRecord = try await cloudKit.save(record)

            if let savedBlock = TimeBlock(from: savedRecord) {
                recordIDMapping[savedBlock.id] = savedRecord.recordID

                // Update cache
                if let index = timeBlocks.firstIndex(where: { $0.id == savedBlock.id }) {
                    timeBlocks[index] = savedBlock
                } else {
                    timeBlocks.append(savedBlock)
                    timeBlocks.sort { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
                }

                return savedBlock
            }

            return clamped
        } catch {
            self.error = error
            throw error
        }
    }

    /// Save multiple time blocks (each clamped to the care time window; blocks entirely outside are dropped)
    func saveAll(_ blocks: [TimeBlock]) async throws -> [TimeBlock] {
        let currentProvider = User.loadLocal()?.asCareProvider.rawValue
        let clampedBlocks = blocks.compactMap { block -> TimeBlock? in
            var stamped = block
            stamped.lastModifiedBy = currentProvider
            return stamped.clampedToCareWindow()
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        // Local-only mode
        guard cloudKit.isAuthenticated else {
            print("[TimeBlockRepository] saveAll() — CloudKit not authenticated, using local storage for \(clampedBlocks.count) blocks")
            for block in clampedBlocks {
                if let index = timeBlocks.firstIndex(where: { $0.id == block.id }) {
                    timeBlocks[index] = block
                } else {
                    timeBlocks.append(block)
                }
            }
            timeBlocks.sort { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
            return clampedBlocks
        }
        print("[TimeBlockRepository] saveAll() — CloudKit authenticated, saving \(clampedBlocks.count) blocks to CloudKit")

        do {
            let records = clampedBlocks.map { $0.toRecord(recordID: recordIDMapping[$0.id]) }
            let savedRecords = try await cloudKit.batchSave(records)

            if savedRecords.count < clampedBlocks.count {
                print("[TimeBlockRepository] ⚠️ saveAll: only \(savedRecords.count)/\(clampedBlocks.count) records saved to CloudKit")
            }

            let savedBlocks = savedRecords.compactMap { record -> TimeBlock? in
                guard let block = TimeBlock(from: record) else { return nil }
                recordIDMapping[block.id] = record.recordID
                return block
            }

            // Update cache with saved blocks
            for block in savedBlocks {
                if let index = timeBlocks.firstIndex(where: { $0.id == block.id }) {
                    timeBlocks[index] = block
                } else {
                    timeBlocks.append(block)
                }
            }
            timeBlocks.sort { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }

            return savedBlocks
        } catch {
            print("[TimeBlockRepository] saveAll FAILED: \(error.localizedDescription)")
            self.error = error
            throw error
        }
    }

    // MARK: - Delete Operations

    /// Delete a time block
    func delete(_ block: TimeBlock) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard cloudKit.isAuthenticated else {
            // Local-only mode
            timeBlocks.removeAll { $0.id == block.id }
            return
        }

        guard let recordID = recordIDMapping[block.id] else {
            timeBlocks.removeAll { $0.id == block.id }
            return
        }

        do {
            try await cloudKit.delete(recordID: recordID)
            recordIDMapping.removeValue(forKey: block.id)
            timeBlocks.removeAll { $0.id == block.id }
        } catch {
            self.error = error
            throw error
        }
    }

    // MARK: - Overlap Resolution

    /// Remove existing blocks that overlap with the incoming blocks.
    /// Handles recurring blocks by checking if they apply to the same day.
    /// Returns the list of blocks that were removed.
    @discardableResult
    func removeOverlapping(with incomingBlocks: [TimeBlock]) async throws -> [TimeBlock] {
        let calendar = Calendar.current
        var removed: [TimeBlock] = []

        for incoming in incomingBlocks {
            guard incoming.isValid else { continue }
            let incomingDay = calendar.startOfDay(for: incoming.date)

            // Find existing blocks that occupy overlapping slots on the same effective day
            let overlapping = timeBlocks.filter { existing in
                // Don't conflict with itself
                guard existing.id != incoming.id else { return false }

                // Check if the existing block applies to the same day
                let appliesToSameDay: Bool
                if calendar.isDate(existing.date, inSameDayAs: incomingDay) {
                    appliesToSameDay = true
                } else if existing.recurrenceType != .none {
                    appliesToSameDay = existing.matchesRecurrence(on: incomingDay)
                } else {
                    appliesToSameDay = false
                }
                guard appliesToSameDay else { return false }

                // Check slot overlap
                return incoming.startSlot < existing.endSlot && incoming.endSlot > existing.startSlot
            }

            for block in overlapping where !removed.contains(where: { $0.id == block.id }) {
                try await delete(block)
                removed.append(block)
            }
        }

        return removed
    }

    // MARK: - Local Operations

    /// Get blocks for a specific date from cache (includes recurring blocks that apply)
    func blocksForDate(_ date: Date) -> [TimeBlock] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        return timeBlocks.filter { block in
            if calendar.isDate(block.date, inSameDayAs: date) {
                return true
            }
            // Check if a recurring block applies to this date
            if block.recurrenceType != .none,
               block.date <= targetDay,
               (block.recurrenceEndDate == nil || block.recurrenceEndDate! >= targetDay) {
                return block.matchesRecurrence(on: date)
            }
            return false
        }
        .sorted { $0.startSlot < $1.startSlot }
    }

    /// Get blocks for a provider from cache
    func blocksForProvider(_ provider: CareProvider) -> [TimeBlock] {
        timeBlocks.filter { $0.provider == provider }
    }

    /// Clear local cache
    func clearCache() {
        timeBlocks.removeAll()
        recordIDMapping.removeAll()
    }

    /// Clear sample data (call when CloudKit becomes available)
    func clearSampleData() {
        timeBlocks.removeAll()
        recordIDMapping.removeAll()
    }

    /// Replace all blocks with a new set (used after CloudKit fetch)
    func replaceBlocks(_ blocks: [TimeBlock]) {
        timeBlocks = blocks.sorted { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
    }

    // MARK: - Helpers

    private func mergeBlocks(existing: [TimeBlock], fetched: [TimeBlock]) -> [TimeBlock] {
        var merged = existing

        for block in fetched {
            if let index = merged.firstIndex(where: { $0.id == block.id }) {
                merged[index] = block
            } else {
                merged.append(block)
            }
        }

        return merged.sorted { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
    }
}

// MARK: - Sample Data Support

extension TimeBlockRepository {
    /// Load sample data for preview/testing.
    /// Creates recurring weekly blocks anchored to the current week's days
    /// so they appear across all weeks automatically.
    func loadSampleData() {
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return }

        // Create one set of recurring weekly blocks for each day of the current week
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) {
                let blocks = TimeBlock.sampleBlocks(for: date, recurring: true)
                timeBlocks.append(contentsOf: blocks)
            }
        }

        timeBlocks.sort { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
    }
}
