import Foundation

/// Tracks per-operation results when applying a schedule change batch.
/// Allows the UI to distinguish full success, partial success, and total failure.
struct BatchApplyResult {
    var deletedBlocks: [TimeBlock] = []
    var failedDeletes: [TimeBlock] = []
    var savedBlocks: [TimeBlock] = []
    var failedSaves: [TimeBlock] = []
    /// A fatal error that prevented the batch from running at all (e.g. applyAll() crash).
    var fatalError: Error?

    var isFullSuccess: Bool {
        failedDeletes.isEmpty && failedSaves.isEmpty && fatalError == nil
    }

    var isPartialSuccess: Bool {
        !isFullSuccess && totalSucceeded > 0
    }

    var isTotalFailure: Bool {
        totalSucceeded == 0 && totalFailed > 0
    }

    var totalSucceeded: Int {
        deletedBlocks.count + savedBlocks.count
    }

    var totalFailed: Int {
        failedDeletes.count + failedSaves.count
    }

    /// Human-readable summary of what succeeded.
    var successSummary: String {
        var parts: [String] = []
        if !deletedBlocks.isEmpty {
            parts.append("\(deletedBlocks.count) removed")
        }
        if !savedBlocks.isEmpty {
            parts.append("\(savedBlocks.count) saved")
        }
        return parts.joined(separator: ", ")
    }

    /// Human-readable summary of what failed.
    var failureSummary: String {
        var parts: [String] = []
        if !failedDeletes.isEmpty {
            parts.append("\(failedDeletes.count) could not be removed")
        }
        if !failedSaves.isEmpty {
            parts.append("\(failedSaves.count) could not be saved")
        }
        return parts.joined(separator: ", ")
    }
}
