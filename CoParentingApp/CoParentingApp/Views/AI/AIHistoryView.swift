import SwiftUI

/// View displaying past AI interactions for debugging and review.
struct AIHistoryView: View {
    private var log: AIInteractionLog { AIInteractionLog.shared }
    @State private var showingClearConfirm = false

    var body: some View {
        List {
            if log.interactions.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "wand.and.stars",
                    description: Text("AI interactions will appear here after you use the schedule assistant.")
                )
            } else {
                ForEach(log.interactions) { entry in
                    AIHistoryRow(entry: entry)
                }
            }
        }
        .navigationTitle("AI History")
        .toolbar {
            if !log.interactions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
        }
        .confirmationDialog("Clear all AI history?", isPresented: $showingClearConfirm) {
            Button("Clear All", role: .destructive) {
                log.clearAll()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

/// A single row in the AI history list.
struct AIHistoryRow: View {
    let entry: AIInteraction
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: timestamp + status badge
            HStack {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                statusBadge
            }

            // Command
            VStack(alignment: .leading, spacing: 4) {
                Text("Command")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(entry.command)
                    .font(.subheadline)
                    .lineLimit(isExpanded ? nil : 2)
            }

            // Response summary
            VStack(alignment: .leading, spacing: 4) {
                Text("Response")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 3)
            }

            // Error if present
            if let error = entry.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textCase(.uppercase)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(isExpanded ? nil : 2)
                }
            }

            // Change count
            if entry.changeCount > 0 {
                Text("\(entry.changeCount) change\(entry.changeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            // Expand/collapse
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if entry.errorMessage != nil {
            Label("Error", systemImage: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        } else if entry.wasApplied {
            Label("Applied", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        } else {
            Label("Cancelled", systemImage: "minus.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
