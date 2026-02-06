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
            let rangeStart = calendar.date(byAdding: .weekOfYear, value: -2, to: selectedDate)!
            let rangeEnd   = calendar.date(byAdding: .weekOfYear, value: 4, to: selectedDate)!
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
    static func expandRecurringBlocks(_ blocks: [TimeBlock], from rangeStart: Date, to rangeEnd: Date) -> [TimeBlock] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)
        var result: [TimeBlock] = []

        for block in blocks {
            if block.recurrenceType == .none {
                result.append(block)
                continue
            }

            // For recurring templates, generate a concrete instance for every
            // matching date in the display range.
            let effectiveEnd: Date
            if let recEnd = block.recurrenceEndDate {
                effectiveEnd = min(calendar.startOfDay(for: recEnd), end)
            } else {
                effectiveEnd = end
            }

            // Walk dates from the block's base date (or rangeStart, whichever is later)
            let baseDay = calendar.startOfDay(for: block.date)
            var cursor = baseDay < start ? start : baseDay

            while cursor <= effectiveEnd {
                if block.matchesRecurrence(on: cursor) {
                    var instance = block
                    instance.date = cursor
                    result.append(instance)
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
            let batch = try await aiService.parseScheduleCommand(command, currentBlocks: timeBlocks, currentUser: User.loadLocal())
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
        guard let user = User.loadLocal() else { return }

        // Generate all metadata in a single AI call
        let metadata = await aiService.generateActivityMetadata(
            narration: batch.originalCommand,
            summary: batch.summary,
            changeCount: batch.changeCount,
            userName: user.displayName
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
            rawAISummary: batch.summary
        )

        await ScheduleChangeRepository.shared.save(entry)
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
