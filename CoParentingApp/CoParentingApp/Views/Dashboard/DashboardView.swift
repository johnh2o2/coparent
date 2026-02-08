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
                    AIEntryCard(showAIAssistant: $showAIAssistant)
                        .padding(.horizontal)

                    // Year at a Glance card
                    YearAtAGlanceCard(viewModel: viewModel)
                        .padding(.horizontal)

                    // This Week mini-schedule
                    if !viewModel.thisWeekBlocks.isEmpty {
                        ThisWeekStrip(blocks: viewModel.thisWeekBlocks)
                            .padding(.horizontal)
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
