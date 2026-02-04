import Foundation

/// A batch of schedule changes produced by a single AI command.
/// Groups multiple `ScheduleChange` items so that complex commands
/// (e.g. "set up a weekly schedule") can be reviewed and applied atomically.
struct ScheduleChangeBatch: Identifiable, Equatable {
    let id: UUID
    let changes: [ScheduleChange]
    let summary: String
    let originalCommand: String

    init(
        id: UUID = UUID(),
        changes: [ScheduleChange],
        summary: String,
        originalCommand: String
    ) {
        self.id = id
        self.changes = changes
        self.summary = summary
        self.originalCommand = originalCommand
    }

    var changeCount: Int { changes.count }

    /// Apply all changes in the batch, returning blocks to save and blocks to delete.
    func applyAll() -> (toSave: [TimeBlock], toDelete: [TimeBlock]) {
        var toSave: [TimeBlock] = []
        var toDelete: [TimeBlock] = []
        for change in changes {
            toSave.append(contentsOf: change.apply())
            if change.changeType == .removeBlock, let original = change.originalBlock {
                toDelete.append(original)
            }
        }
        return (toSave, toDelete)
    }
}

// MARK: - Sample Data

extension ScheduleChangeBatch {
    static var sampleBatch: ScheduleChangeBatch {
        ScheduleChangeBatch(
            changes: [ScheduleChange.sampleTimeChange],
            summary: "Adjusted pickup time to 8:15 AM",
            originalCommand: "Move pickup to 8:15 AM"
        )
    }
}
