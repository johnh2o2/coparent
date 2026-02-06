import SwiftUI

/// Home tab showing care balance dashboard and recent activity.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Greeting
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.greeting)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text(viewModel.todayString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Year at a Glance card
                    yearAtAGlanceCard

                    // This Week mini-schedule
                    if !viewModel.thisWeekBlocks.isEmpty {
                        thisWeekSection
                    }

                    // Recent Activity
                    if !viewModel.recentActivity.isEmpty {
                        recentActivitySection
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if viewModel.isLoading && viewModel.totalHours == 0 {
                    ProgressView()
                }
            }
            .task {
                await viewModel.loadDashboard()
            }
            .refreshable {
                await viewModel.loadDashboard()
            }
        }
    }

    // MARK: - Year at a Glance

    private var yearAtAGlanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(Color.accentColor)
                Text("Year at a Glance")
                    .font(.headline)
            }

            // Two columns: Parent A + Parent B
            HStack(spacing: 20) {
                providerColumn(
                    name: CareProvider.parentA.displayName,
                    hours: viewModel.parentAHours,
                    color: CareProvider.parentA.color
                )

                providerColumn(
                    name: CareProvider.parentB.displayName,
                    hours: viewModel.parentBHours,
                    color: CareProvider.parentB.color
                )
            }

            // Balance bar
            balanceBar

            // Balance message
            balanceMessage

            // Nanny hours (if any)
            if viewModel.nannyHours > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CareProvider.nanny.color)
                        .frame(width: 8, height: 8)
                    Text("\(CareProvider.nanny.displayName): \(String(format: "%.0f", viewModel.nannyHours))h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .padding(.horizontal)
    }

    private func providerColumn(name: String, hours: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(String(format: "%.0f", hours))
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text("hours")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var balanceBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let aWidth = width * viewModel.parentAFraction
            let bWidth = width * viewModel.parentBFraction

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(CareProvider.parentA.color)
                    .frame(width: max(aWidth, 4))

                RoundedRectangle(cornerRadius: 4)
                    .fill(CareProvider.parentB.color)
                    .frame(width: max(bWidth, 4))
            }
        }
        .frame(height: 12)
    }

    private var balanceMessage: some View {
        Group {
            if viewModel.totalHours == 0 {
                Text("No schedule data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.isBalanced {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Nicely balanced")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("\(String(format: "%.0f", viewModel.balanceDelta))h apart — you might want to plan together to close the gap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - This Week

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let calendar = Calendar.current
                    let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!

                    ForEach(0..<7, id: \.self) { dayOffset in
                        let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
                        let dayBlocks = viewModel.thisWeekBlocks.filter {
                            calendar.isDate($0.date, inSameDayAs: date)
                        }.sorted { $0.startSlot < $1.startSlot }

                        miniDayColumn(date: date, blocks: dayBlocks, isToday: calendar.isDateInToday(date))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func miniDayColumn(date: Date, blocks: [TimeBlock], isToday: Bool) -> some View {
        VStack(spacing: 4) {
            Text(dayAbbreviation(date))
                .font(.caption2)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : .secondary)

            VStack(spacing: 1) {
                if blocks.isEmpty {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(width: 36, height: 40)
                } else {
                    ForEach(blocks.prefix(4)) { block in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(block.provider.color)
                            .frame(width: 36, height: max(4, CGFloat(block.durationMinutes) / 15))
                    }
                }
            }
            .frame(minWidth: 36, minHeight: 40)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isToday ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func dayAbbreviation(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(viewModel.recentActivity) { entry in
                    NavigationLink(destination: ActivityDetailView(entry: entry)) {
                        recentActivityRow(entry)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
                }
            }
            .padding(.horizontal)
        }
    }

    private func recentActivityRow(_ entry: ScheduleChangeEntry) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.provider.color)
                .frame(width: 3)

            Image(systemName: "wand.and.stars")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)

            Text(entry.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            Text(relativeTime(entry.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(entry.provider.lightColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}
