import SwiftUI

/// Raw input/output view for a schedule change — shows the user's request and AI response.
struct ActivityRawView: View {
    let entry: ScheduleChangeEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // User's request
                if let narration = entry.userNarration, !narration.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your Request", systemImage: "text.bubble")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Text(narration)
                            .font(.system(.subheadline, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // AI response (raw summary)
                if let rawSummary = entry.rawAISummary, !rawSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Response", systemImage: "wand.and.stars")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        // Try to render as markdown, fallback to plain text
                        if let attributed = try? AttributedString(
                            markdown: rawSummary,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                        ) {
                            Text(attributed)
                                .font(.subheadline)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Text(rawSummary)
                                .font(.subheadline)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // Metadata summary
                VStack(alignment: .leading, spacing: 12) {
                    Label("Change Summary", systemImage: "list.bullet.rectangle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        metadataRow(label: "Title", value: entry.title)
                        metadataRow(label: "Changes", value: "\(entry.changesApplied)")
                        metadataRow(label: "Dates", value: entry.datesImpacted)
                        if let delta = entry.careTimeDelta {
                            metadataRow(label: "Care Delta", value: delta)
                        }
                        if let purpose = entry.purpose {
                            metadataRow(label: "Purpose", value: purpose)
                        }
                        metadataRow(label: "By", value: "\(entry.userName) (\(entry.provider.displayName))")
                        metadataRow(label: "When", value: fullTimestamp)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Raw Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(value)
                .font(.caption)
        }
    }

    private var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter.string(from: entry.timestamp)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ActivityRawView(entry: ScheduleChangeEntry(
            userID: UUID(),
            userName: "John Hoffman",
            userRole: "parent_a",
            changeDescription: "Updated the weekly schedule",
            userNarration: "Set up M/W/F for me, T/Th for parent B",
            notificationMessage: "John updated the weekly schedule.",
            changesApplied: 10,
            title: "Set weekly schedule",
            purpose: "Establishing a recurring weekly pattern",
            datesImpacted: "Mon-Fri recurring, starting Feb 10",
            careTimeDelta: "+37.5h Parent A weekly",
            rawAISummary: "I've set up a **recurring weekly** schedule with the following pattern:\n\n- Monday/Wednesday/Friday: Parent A covers 7:00 AM - 7:30 PM\n- Tuesday/Thursday: Parent B covers 7:00 AM - 7:30 PM"
        ))
    }
}
