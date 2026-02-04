import SwiftUI

/// View for reviewing and approving an AI-suggested batch of schedule changes
struct BatchApprovalView: View {
    let batch: ScheduleChangeBatch
    let onApprove: () -> Void
    let onReject: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 40))
                            .foregroundStyle(.purple)

                        Text("Review Changes")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Label("AI Suggestion", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.purple.opacity(0.1))
                            .clipShape(Capsule())

                        Text("\(batch.changeCount) change\(batch.changeCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)

                    // Summary
                    VStack(alignment: .leading, spacing: 16) {
                        Text(batch.summary)
                            .font(.body)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    // Individual changes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Changes")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(batch.changes) { change in
                            BatchChangeRow(change: change)
                                .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 40)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            onApprove()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Apply All Changes")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            onReject()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "xmark")
                                Text("Reject")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Approve Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onReject()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Row displaying a single change within a batch
struct BatchChangeRow: View {
    let change: ScheduleChange

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: changeIcon)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(change.description)
                    .font(.subheadline)

                if let explanation = change.aiExplanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var changeIcon: String {
        switch change.changeType {
        case .changeTime: return "clock.arrow.2.circlepath"
        case .swap: return "arrow.left.arrow.right"
        case .addBlock: return "plus.circle.fill"
        case .removeBlock: return "minus.circle.fill"
        case .reassign: return "person.2.gobackward"
        }
    }

    private var iconColor: Color {
        switch change.changeType {
        case .addBlock: return .green
        case .removeBlock: return .red
        default: return .purple
        }
    }
}

/// View for reviewing and approving a single AI-suggested schedule change
struct ScheduleChangeApprovalView: View {
    let change: ScheduleChange
    let onApprove: () -> Void
    let onReject: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 40))
                            .foregroundStyle(.purple)

                        Text("Review Change")
                            .font(.title2)
                            .fontWeight(.semibold)

                        if change.suggestedByAI {
                            Label("AI Suggestion", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.purple.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top)

                    // Change description
                    VStack(alignment: .leading, spacing: 16) {
                        Text(change.description)
                            .font(.body)

                        if let explanation = change.aiExplanation {
                            Text(explanation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)

                    // Before/After comparison
                    if change.originalBlock != nil || change.proposedBlock != nil {
                        ChangeComparisonView(change: change)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            onApprove()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Approve Change")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            onReject()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "xmark")
                                Text("Reject")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Approve Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onReject()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Side-by-side comparison of before and after
struct ChangeComparisonView: View {
    let change: ScheduleChange

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Before
                if let original = change.originalBlock {
                    ComparisonCard(
                        title: "Before",
                        block: original,
                        isRemoved: change.changeType == .removeBlock
                    )
                }

                // Arrow
                if change.originalBlock != nil && change.proposedBlock != nil {
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                // After
                if let proposed = change.proposedBlock {
                    ComparisonCard(
                        title: "After",
                        block: proposed,
                        isNew: change.changeType == .addBlock
                    )
                }
            }

            // Secondary blocks for swaps
            if change.changeType == .swap,
               let secondOriginal = change.secondaryOriginalBlock,
               let secondProposed = change.secondaryProposedBlock {
                Divider()

                HStack(spacing: 16) {
                    ComparisonCard(
                        title: "Before",
                        block: secondOriginal,
                        isRemoved: false
                    )

                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    ComparisonCard(
                        title: "After",
                        block: secondProposed,
                        isNew: false
                    )
                }
            }
        }
    }
}

/// Individual comparison card showing a time block
struct ComparisonCard: View {
    let title: String
    let block: TimeBlock
    var isRemoved = false
    var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if isRemoved {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                } else if isNew {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                // Date
                Text(block.date.shortDateString)
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Time range
                Text(SlotUtility.formatSlotRange(start: block.startSlot, end: block.endSlot))
                    .font(.callout)

                // Provider
                HStack(spacing: 6) {
                    Circle()
                        .fill(block.provider.color)
                        .frame(width: 10, height: 10)
                    Text(block.provider.displayName)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isRemoved ? Color.red.opacity(0.1) : (isNew ? Color.green.opacity(0.1) : Color(.systemGray6)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isRemoved ? .red.opacity(0.3) : (isNew ? .green.opacity(0.3) : .clear), lineWidth: 2)
        )
    }
}

/// Full screen view for multiple pending batches
struct PendingBatchesListView: View {
    let batches: [ScheduleChangeBatch]
    let onApprove: (ScheduleChangeBatch) -> Void
    let onReject: (ScheduleChangeBatch) -> Void
    let onApproveAll: () -> Void
    let onRejectAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(batches) { batch in
                    PendingBatchRow(
                        batch: batch,
                        onApprove: { onApprove(batch) },
                        onReject: { onReject(batch) }
                    )
                }
            }
            .navigationTitle("Pending Batches (\(batches.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject All") {
                        onRejectAll()
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve All") {
                        onApproveAll()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

/// Row for a single pending batch
struct PendingBatchRow: View {
    let batch: ScheduleChangeBatch
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.purple)
                        Text("\(batch.changeCount) Change\(batch.changeCount == 1 ? "" : "s")")
                            .font(.headline)
                    }

                    Text(batch.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    onReject()
                } label: {
                    Text("Reject")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Button {
                    onApprove()
                } label: {
                    Text("Apply All")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.green)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview("Single Change") {
    ScheduleChangeApprovalView(
        change: ScheduleChange.sampleTimeChange,
        onApprove: {},
        onReject: {}
    )
}

#Preview("Batch Approval") {
    BatchApprovalView(
        batch: ScheduleChangeBatch.sampleBatch,
        onApprove: {},
        onReject: {}
    )
}
