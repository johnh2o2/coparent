import SwiftUI

/// Detail view for a single activity journal entry.
struct ActivityDetailView: View {
    let entry: ScheduleChangeEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Purpose (if present)
                if let purpose = entry.purpose, !purpose.isEmpty {
                    purposeSection(purpose)
                }

                // Impact: dates + care time delta
                impactSection

                // Notification message
                notificationSection

                // View Raw Details link
                NavigationLink(destination: ActivityRawView(entry: entry)) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("View Raw Details")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Activity Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(entry.title)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(entry.provider.gradient)
                        .frame(width: 40, height: 40)

                    Text(User.initials(from: entry.userName))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.userName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Image(systemName: "wand.and.stars")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(fullTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Changes count
                Text("\(entry.changesApplied) change\(entry.changesApplied == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Purpose

    private func purposeSection(_ purpose: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Purpose", systemImage: "lightbulb")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(purpose)
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Impact

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Impact on Your Year", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                if let delta = entry.careTimeDelta, !delta.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(entry.provider.color)
                        Text(delta)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(entry.provider.color)
                    Text(entry.datesImpacted)
                        .font(.subheadline)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(entry.provider.lightColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Notification

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notification", systemImage: "bell")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(entry.notificationMessage)
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ActivityDetailView(entry: ScheduleChangeEntry(
            userID: UUID(),
            userName: "John Hoffman",
            userRole: "parent_a",
            changeDescription: "Updated the weekly schedule",
            userNarration: "Set up M/W/F for me, T/Th for parent B",
            notificationMessage: "John updated the weekly schedule — he now covers Mon/Wed/Fri and you have Tuesdays and Thursdays.",
            changesApplied: 10,
            title: "John takes Mon/Wed/Fri, setting default schedule",
            purpose: "Establishing a recurring weekly pattern for consistent childcare coverage",
            datesImpacted: "Mon-Fri recurring, starting Feb 10",
            careTimeDelta: "+487h to your year",
            rawAISummary: "I've set up a recurring weekly schedule..."
        ))
    }
}
