import Foundation
import SwiftUI
import KVKCalendar

/// ViewModel for calendar-related operations
@Observable
final class CalendarViewModel {
    private let repository: TimeBlockRepository
    private let aiService: AIScheduleService

    // State
    var selectedDate = Date()
    var calendarType: CalendarType = .week
    /// Raw blocks from the repository — recurring templates stay as templates here.
    /// Used for AI context and data management.
    var timeBlocks: [TimeBlock] = []
    /// Expanded blocks for calendar display — recurring templates are expanded
    /// into concrete per-day instances so they appear on every applicable date.
    var displayBlocks: [TimeBlock] = []
    var selectedBlock: TimeBlock?
    var pendingBatches: [ScheduleChangeBatch] = []

    var isLoading = false
    var errorMessage: String?

    /// The date range currently loaded, used to expand recurring blocks.
    private var loadedRangeStart: Date = Date()
    private var loadedRangeEnd: Date = Date()

    // Editor state
    var isEditorPresented = false
    var isAIAssistantPresented = false
    var editingBlock: TimeBlock?

    init(repository: TimeBlockRepository = .shared, aiService: AIScheduleService = AIScheduleService()) {
        self.repository = repository
        self.aiService = aiService
    }

    // MARK: - Data Loading

    /// Load blocks for the current view.
    /// Loads a generous range around the selected date so the calendar has
    /// enough data for scrolling and view-type switching without re-fetching.
    func loadBlocks() async {
        isLoading = true
        errorMessage = nil

        do {
            let calendar = Calendar.current

            // Load a broad range around the selected date so the calendar has
            // enough data for scrolling and view-type switching.
            // Use months instead of weeks so monthly view has data when navigating.
            let rangeStart = calendar.date(byAdding: .month, value: -2, to: selectedDate)!
            let rangeEnd   = calendar.date(byAdding: .month, value: 4, to: selectedDate)!
            loadedRangeStart = rangeStart
            loadedRangeEnd = rangeEnd

            timeBlocks = try await repository.fetchBlocks(from: rangeStart, to: rangeEnd)
            displayBlocks = Self.expandRecurringBlocks(timeBlocks, from: rangeStart, to: rangeEnd)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Expand recurring template blocks into concrete per-day instances for the
    /// given date range.  Non-recurring blocks pass through as-is.
    ///
    /// When a non-recurring block exists on a given day, any recurring instances
    /// that overlap with it are suppressed.  This allows single-day overrides
    /// without permanently deleting the recurring template.
    static func expandRecurringBlocks(_ blocks: [TimeBlock], from rangeStart: Date, to rangeEnd: Date) -> [TimeBlock] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)

        // Collect non-recurring blocks first — these take priority
        let nonRecurring = blocks.filter { $0.recurrenceType == .none }

        // Index non-recurring blocks by day for fast overlap lookup
        var overridesByDay: [Date: [TimeBlock]] = [:]
        for block in nonRecurring {
            let day = calendar.startOfDay(for: block.date)
            overridesByDay[day, default: []].append(block)
        }

        var result: [TimeBlock] = nonRecurring

        for block in blocks {
            guard block.recurrenceType != .none else { continue }

            let effectiveEnd: Date
            if let recEnd = block.recurrenceEndDate {
                effectiveEnd = min(calendar.startOfDay(for: recEnd), end)
            } else {
                effectiveEnd = end
            }

            let baseDay = calendar.startOfDay(for: block.date)
            var cursor = baseDay < start ? start : baseDay

            while cursor <= effectiveEnd {
                if block.matchesRecurrence(on: cursor) {
                    // Check if a non-recurring override on this day overlaps this slot range
                    let dayOverrides = overridesByDay[cursor] ?? []
                    let isOverridden = dayOverrides.contains { override in
                        override.startSlot < block.endSlot && override.endSlot > block.startSlot
                    }

                    if !isOverridden {
                        var instance = block
                        instance.date = cursor
                        result.append(instance)
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        return result.sorted { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
    }

    /// Recompute displayBlocks from the current timeBlocks and loaded range.
    private func rebuildDisplayBlocks() {
        displayBlocks = Self.expandRecurringBlocks(timeBlocks, from: loadedRangeStart, to: loadedRangeEnd)
    }

    /// Check if a date is outside the currently loaded range (with some margin).
    func isOutsideLoadedRange(_ date: Date) -> Bool {
        let calendar = Calendar.current
        // Use a 1-month inner margin so we reload before hitting the edge
        guard let safeStart = calendar.date(byAdding: .month, value: 1, to: loadedRangeStart),
              let safeEnd = calendar.date(byAdding: .month, value: -1, to: loadedRangeEnd) else {
            return true
        }
        return date < safeStart || date > safeEnd
    }

    /// Refresh data
    func refresh() async {
        await loadBlocks()
    }

    // MARK: - Block Operations

    /// Get blocks for a specific date (includes recurring blocks that apply)
    func blocks(for date: Date) -> [TimeBlock] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        return timeBlocks.filter { block in
            if calendar.isDate(block.date, inSameDayAs: date) {
                return true
            }
            if block.recurrenceType != .none,
               block.date <= targetDay,
               (block.recurrenceEndDate == nil || block.recurrenceEndDate! >= targetDay) {
                return block.matchesRecurrence(on: date)
            }
            return false
        }
        .sorted { $0.startSlot < $1.startSlot }
    }

    /// Create a new block
    func createBlock(date: Date, startSlot: Int, endSlot: Int, provider: CareProvider, notes: String? = nil) async {
        let block = TimeBlock(
            date: date,
            startSlot: startSlot,
            endSlot: endSlot,
            provider: provider,
            notes: notes
        )

        isLoading = true
        errorMessage = nil

        do {
            let saved = try await repository.save(block)
            timeBlocks.append(saved)
            timeBlocks.sort { $0.date < $1.date || ($0.date == $1.date && $0.startSlot < $1.startSlot) }
            rebuildDisplayBlocks()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Update an existing block
    func updateBlock(_ block: TimeBlock) async {
        isLoading = true
        errorMessage = nil

        do {
            let saved = try await repository.save(block)
            if let index = timeBlocks.firstIndex(where: { $0.id == saved.id }) {
                timeBlocks[index] = saved
            }
            rebuildDisplayBlocks()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Delete a block
    func deleteBlock(_ block: TimeBlock) async {
        isLoading = true
        errorMessage = nil

        do {
            try await repository.delete(block)
            timeBlocks.removeAll { $0.id == block.id }
            rebuildDisplayBlocks()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Move a block (from drag operation)
    func moveBlock(_ block: TimeBlock, to newDate: Date, startSlot: Int, endSlot: Int) async {
        var updatedBlock = block
        updatedBlock.date = newDate
        updatedBlock.startSlot = startSlot
        updatedBlock.endSlot = endSlot
        updatedBlock.modifiedAt = Date()

        await updateBlock(updatedBlock)
    }

    // MARK: - Editor Actions

    /// Open editor for a new block
    func openNewBlockEditor(date: Date, startSlot: Int, endSlot: Int) {
        editingBlock = TimeBlock(
            date: date,
            startSlot: startSlot,
            endSlot: endSlot,
            provider: .parentA
        )
        isEditorPresented = true
    }

    /// Open editor for an existing block
    func openBlockEditor(_ block: TimeBlock) {
        editingBlock = block
        isEditorPresented = true
    }

    /// Save the editing block
    func saveEditingBlock() async {
        guard let block = editingBlock else { return }

        if timeBlocks.contains(where: { $0.id == block.id }) {
            await updateBlock(block)
        } else {
            await createBlock(
                date: block.date,
                startSlot: block.startSlot,
                endSlot: block.endSlot,
                provider: block.provider,
                notes: block.notes
            )
        }

        editingBlock = nil
        isEditorPresented = false
    }

    /// Cancel editing
    func cancelEditing() {
        editingBlock = nil
        isEditorPresented = false
    }

    // MARK: - AI Operations

    /// Process an AI command, returning a batch of proposed changes.
    func processAICommand(_ command: String) async -> ScheduleChangeBatch? {
        isLoading = true
        errorMessage = nil

        do {
            let batch = try await aiService.parseScheduleCommand(command, currentBlocks: timeBlocks, currentUser: UserProfileManager.shared.currentUser)
            pendingBatches.append(batch)
            isLoading = false
            return batch
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    /// Apply all changes in a batch.
    func applyBatch(_ batch: ScheduleChangeBatch) async {
        isLoading = true
        errorMessage = nil

        do {
            let (toSave, toDelete) = batch.applyAll()

            for block in toDelete {
                try await repository.delete(block)
            }

            // Remove existing blocks that overlap with new ones
            let validToSave = toSave.filter { $0.isValid }
            if !validToSave.isEmpty {
                try await repository.removeOverlapping(with: validToSave)
                let _ = try await repository.saveAll(validToSave)
            }

            // Reload from repository for the current view range
            await loadBlocks()

            // Remove from pending
            pendingBatches.removeAll { $0.id == batch.id }

            // Log to activity journal
            await logActivityEntry(for: batch)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Log an activity journal entry after a batch is applied.
    private func logActivityEntry(for batch: ScheduleChangeBatch) async {
        guard let user = UserProfileManager.shared.currentUser else { return }

        // Build a structured breakdown of changes for better metadata
        let breakdown = Self.buildChangeBreakdown(batch)
        // Build the full per-change detail list for drill-down display
        let detailedBreakdown = Self.buildDetailedChangeBreakdown(batch)

        // Generate all metadata in a single AI call
        let metadata = await aiService.generateActivityMetadata(
            narration: batch.originalCommand,
            summary: batch.summary,
            changeCount: batch.changeCount,
            userName: user.displayName,
            userRole: user.role.displayName,
            changeBreakdown: breakdown
        )

        let entry = ScheduleChangeEntry(
            userID: user.id,
            userName: user.displayName,
            userRole: user.asCareProvider.rawValue,
            changeDescription: metadata.notificationMessage,
            userNarration: batch.originalCommand,
            notificationMessage: metadata.notificationMessage,
            changesApplied: batch.changeCount,
            title: metadata.title,
            purpose: metadata.purpose,
            datesImpacted: metadata.datesImpacted,
            careTimeDelta: metadata.careTimeDelta,
            rawAISummary: batch.summary,
            changeBreakdown: detailedBreakdown
        )

        await ScheduleChangeRepository.shared.save(entry)
    }

    /// Build a concise, structured breakdown of changes in a batch for activity metadata.
    static func buildChangeBreakdown(_ batch: ScheduleChangeBatch) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"

        var adds: [String] = []
        var removes: [String] = []
        var modifications: [String] = []
        var isRecurring = false

        for change in batch.changes {
            switch change.changeType {
            case .addBlock:
                if let block = change.proposedBlock {
                    let time = SlotUtility.formatSlotRange(start: block.startSlot, end: block.endSlot)
                    let recur = block.recurrenceType != .none ? " (recurring weekly)" : ""
                    if block.recurrenceType != .none { isRecurring = true }
                    adds.append("\(block.provider.displayName) on \(formatter.string(from: block.date)) \(time)\(recur)")
                }
            case .removeBlock:
                if let block = change.originalBlock {
                    let time = SlotUtility.formatSlotRange(start: block.startSlot, end: block.endSlot)
                    removes.append("\(block.provider.displayName) on \(formatter.string(from: block.date)) \(time)")
                }
            case .changeTime:
                if let orig = change.originalBlock, let prop = change.proposedBlock {
                    let oldTime = SlotUtility.formatSlotRange(start: orig.startSlot, end: orig.endSlot)
                    let newTime = SlotUtility.formatSlotRange(start: prop.startSlot, end: prop.endSlot)
                    modifications.append("\(orig.provider.displayName): \(oldTime) → \(newTime) on \(formatter.string(from: prop.date))")
                }
            case .swap:
                if let orig = change.originalBlock, let sec = change.secondaryOriginalBlock {
                    modifications.append("Swapped \(formatter.string(from: orig.date)) (\(orig.provider.displayName)) with \(formatter.string(from: sec.date)) (\(sec.provider.displayName))")
                }
            case .reassign:
                if let orig = change.originalBlock, let prop = change.proposedBlock {
                    modifications.append("Reassigned \(formatter.string(from: orig.date)) from \(orig.provider.displayName) to \(prop.provider.displayName)")
                }
            }
        }

        var lines: [String] = []
        if !adds.isEmpty {
            // Summarize if too many adds (e.g. recurring weekly schedule)
            if adds.count > 6 {
                // Group by provider
                var byProvider: [String: Int] = [:]
                for change in batch.changes where change.changeType == .addBlock {
                    if let block = change.proposedBlock {
                        byProvider[block.provider.displayName, default: 0] += 1
                    }
                }
                let providerSummary = byProvider.map { "\($0.value) blocks for \($0.key)" }.joined(separator: ", ")
                lines.append("Added: \(providerSummary)\(isRecurring ? " (recurring weekly)" : "")")
            } else {
                lines.append("Added: " + adds.joined(separator: "; "))
            }
        }
        if !removes.isEmpty {
            if removes.count > 6 {
                lines.append("Removed: \(removes.count) existing blocks (clearing old schedule)")
            } else {
                lines.append("Removed: " + removes.joined(separator: "; "))
            }
        }
        if !modifications.isEmpty {
            lines.append("Modified: " + modifications.joined(separator: "; "))
        }

        return lines.joined(separator: "\n")
    }

    /// Build a full per-change breakdown with no summarization — used for drill-down display.
    /// Each line is prefixed with a type marker: + (add), - (remove), ~ (modify), ⇄ (swap).
    static func buildDetailedChangeBreakdown(_ batch: ScheduleChangeBatch) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"

        var lines: [String] = []

        for change in batch.changes {
            switch change.changeType {
            case .addBlock:
                if let block = change.proposedBlock {
                    let time = SlotUtility.formatSlotRange(start: block.startSlot, end: block.endSlot)
                    let day = formatter.string(from: block.date)
                    let recur = block.recurrenceType != .none ? " (recurring)" : ""
                    lines.append("+ \(block.provider.displayName): \(day) \(time)\(recur)")
                }
            case .removeBlock:
                if let block = change.originalBlock {
                    let time = SlotUtility.formatSlotRange(start: block.startSlot, end: block.endSlot)
                    let day = formatter.string(from: block.date)
                    let recur = block.recurrenceType != .none ? " (recurring)" : ""
                    lines.append("- \(block.provider.displayName): \(day) \(time)\(recur)")
                }
            case .changeTime:
                if let orig = change.originalBlock, let prop = change.proposedBlock {
                    let oldTime = SlotUtility.formatSlotRange(start: orig.startSlot, end: orig.endSlot)
                    let newTime = SlotUtility.formatSlotRange(start: prop.startSlot, end: prop.endSlot)
                    let day = formatter.string(from: prop.date)
                    lines.append("~ \(orig.provider.displayName): \(oldTime) → \(newTime) on \(day)")
                }
            case .swap:
                if let orig = change.originalBlock, let sec = change.secondaryOriginalBlock {
                    lines.append("⇄ \(formatter.string(from: orig.date)) (\(orig.provider.displayName)) ↔ \(formatter.string(from: sec.date)) (\(sec.provider.displayName))")
                }
            case .reassign:
                if let orig = change.originalBlock, let prop = change.proposedBlock {
                    let day = formatter.string(from: orig.date)
                    let time = SlotUtility.formatSlotRange(start: orig.startSlot, end: orig.endSlot)
                    lines.append("~ \(day) \(time): \(orig.provider.displayName) → \(prop.provider.displayName)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Reject a pending batch.
    func rejectBatch(_ batch: ScheduleChangeBatch) {
        pendingBatches.removeAll { $0.id == batch.id }
    }

    // MARK: - Navigation

    /// Go to today
    func goToToday() {
        selectedDate = Date()
        Task {
            await loadBlocks()
        }
    }

    /// Go to previous period
    func goToPrevious() {
        let calendar = Calendar.current
        switch calendarType {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        default:
            break
        }

        Task {
            await loadBlocks()
        }
    }

    /// Go to next period
    func goToNext() {
        let calendar = Calendar.current
        switch calendarType {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        default:
            break
        }

        Task {
            await loadBlocks()
        }
    }
}

// MARK: - Preview Support

extension CalendarViewModel {
    static var preview: CalendarViewModel {
        let viewModel = CalendarViewModel()
        viewModel.repository.loadSampleData()
        viewModel.timeBlocks = viewModel.repository.timeBlocks
        let calendar = Calendar.current
        let rangeStart = calendar.date(byAdding: .weekOfYear, value: -2, to: Date())!
        let rangeEnd = calendar.date(byAdding: .weekOfYear, value: 4, to: Date())!
        viewModel.displayBlocks = expandRecurringBlocks(viewModel.timeBlocks, from: rangeStart, to: rangeEnd)
        return viewModel
    }
}
