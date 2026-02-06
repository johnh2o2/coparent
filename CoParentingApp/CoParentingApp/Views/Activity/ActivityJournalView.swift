import SwiftUI

/// Chronological feed of schedule changes — compact list with navigation to detail.
struct ActivityJournalView: View {
    @State private var repository = ScheduleChangeRepository.shared
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if repository.entries.isEmpty && !isLoading {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            let grouped = entriesByDay
                            let sortedDays = grouped.keys.sorted(by: >)

                            ForEach(sortedDays, id: \.self) { day in
                                if let dayEntries = grouped[day] {
                                    DaySection(date: day, entries: dayEntries)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Activity")
            .overlay {
                if isLoading && repository.entries.isEmpty {
                    ProgressView()
                }
            }
            .task {
                isLoading = true
                _ = await repository.fetchEntries()
                isLoading = false
            }
            .refreshable {
                _ = await repository.fetchEntries()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No activity yet")
                .font(.title3)
                .fontWeight(.medium)

            Text("Changes you and your coparents make will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var entriesByDay: [Date: [ScheduleChangeEntry]] {
        Dictionary(grouping: repository.entries) { entry in
            Calendar.current.startOfDay(for: entry.timestamp)
        }
    }
}

// MARK: - Day Section

private struct DaySection: View {
    let date: Date
    let entries: [ScheduleChangeEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayHeader)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            ForEach(entries.sorted(by: { $0.timestamp > $1.timestamp })) { entry in
                NavigationLink(destination: ActivityDetailView(entry: entry)) {
                    ActivityEntryCard(entry: entry)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            }
        }
    }

    private var dayHeader: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Compact Activity Entry Card

private struct ActivityEntryCard: View {
    let entry: ScheduleChangeEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left accent stripe
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.provider.color)
                .frame(width: 4)

            // AI wizard icon
            Image(systemName: "wand.and.stars")
                .font(.caption)
                .foregroundStyle(Color.accentColor)

            // Title
            Text(entry.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            // Right side: user name + timestamp + chevron
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.userName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Changes count pill
            if entry.changesApplied > 0 {
                Text("\(entry.changesApplied)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(entry.provider.color.opacity(0.8))
                    .clipShape(Circle())
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(entry.provider.lightColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.timestamp, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    ActivityJournalView()
}
