import SwiftUI

/// Home tab showing care balance dashboard and recent activity.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var calendarViewModel = CalendarViewModel()
    @State private var showAIAssistant = false

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

                    // AI Quick Entry
                    aiEntryCard

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
                await calendarViewModel.loadBlocks()
            }
            .refreshable {
                await viewModel.loadDashboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardShouldReload)) { _ in
                Task {
                    await viewModel.loadDashboard()
                }
            }
            .sheet(isPresented: $showAIAssistant, onDismiss: {
                Task {
                    await viewModel.loadDashboard()
                    await calendarViewModel.loadBlocks()
                }
            }) {
                AIAssistantSheet(calendarViewModel: calendarViewModel)
            }
        }
    }

    // MARK: - AI Quick Entry

    private var aiEntryCard: some View {
        Button {
            showAIAssistant = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))

                Text("What would you like to plan?")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Image(systemName: "mic.fill")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(10)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor,
                        Color.accentColor.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
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

            // Two columns: primary caregivers
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
                    Text("\(CareProvider.nanny.displayName): \(formatDaysAndHours(viewModel.nannyHours))")
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

            Text(formatDaysAndHours(hours))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDaysAndHours(_ totalHours: Double) -> String {
        let days = Int(totalHours) / 24
        let remainingHours = Int(totalHours) % 24
        if days > 0 {
            return "\(days)d \(remainingHours)h"
        }
        return "\(Int(totalHours))h"
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
                Text("\(formatDaysAndHours(viewModel.balanceDelta)) apart — you might want to plan together to close the gap")
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

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let delta = entry.careTimeDelta, !delta.isEmpty {
                    Text(delta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

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
