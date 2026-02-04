import SwiftUI
import Charts

/// View showing care hours summary and statistics
struct CareLogSummaryView: View {
    @State private var viewModel = SummaryViewModel()
    @State private var showingDatePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Date range picker
                    DateRangePicker(
                        selectedRange: $viewModel.selectedRange,
                        startDate: $viewModel.startDate,
                        endDate: $viewModel.endDate,
                        onCustomRange: {
                            showingDatePicker = true
                        }
                    )

                    // Summary cards
                    if let summary = viewModel.summary {
                        SummaryCardsSection(
                            totalHours: summary.totalHours,
                            dayCount: viewModel.dayCount,
                            averagePerDay: viewModel.averageHoursPerDay
                        )

                        // Pie chart
                        ProviderPieChart(data: viewModel.pieChartData)
                            .frame(height: 250)
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Provider breakdown
                        ProviderBreakdownSection(stats: viewModel.providerStats)

                        // Daily bar chart
                        if !viewModel.dailyBreakdown.isEmpty {
                            DailyBarChart(data: viewModel.barChartData)
                                .frame(height: 200)
                                .padding()
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Care Summary")
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                CustomDateRangePicker(
                    startDate: $viewModel.startDate,
                    endDate: $viewModel.endDate,
                    onDone: {
                        viewModel.setCustomRange(
                            start: viewModel.startDate,
                            end: viewModel.endDate
                        )
                        showingDatePicker = false
                    }
                )
            }
            .task {
                await viewModel.loadSummary()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
}

/// Date range picker segment
struct DateRangePicker: View {
    @Binding var selectedRange: SummaryViewModel.DateRange
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onCustomRange: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("Date Range", selection: $selectedRange) {
                ForEach(SummaryViewModel.DateRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Text(formatDateRange())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDateRange() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}

/// Summary statistics cards
struct SummaryCardsSection: View {
    let totalHours: Double
    let dayCount: Int
    let averagePerDay: Double

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Total Hours",
                value: String(format: "%.1f", totalHours),
                icon: "clock.fill",
                color: .blue
            )

            StatCard(
                title: "Days",
                value: "\(dayCount)",
                icon: "calendar",
                color: .green
            )

            StatCard(
                title: "Avg/Day",
                value: String(format: "%.1f", averagePerDay),
                icon: "chart.bar.fill",
                color: .orange
            )
        }
    }
}

/// Individual stat card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Pie chart showing provider distribution
struct ProviderPieChart: View {
    let data: [(provider: CareProvider, hours: Double, color: Color)]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Care Distribution")
                .font(.headline)

            Chart(data, id: \.provider) { item in
                SectorMark(
                    angle: .value("Hours", item.hours),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(item.color)
                .cornerRadius(4)
            }

            // Legend
            HStack(spacing: 16) {
                ForEach(data, id: \.provider) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 10, height: 10)
                        Text("\(item.provider.displayName): \(String(format: "%.1f", item.hours))h")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

/// Provider breakdown section
struct ProviderBreakdownSection: View {
    let stats: [ProviderStatistics]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Provider Breakdown")
                .font(.headline)

            ForEach(stats) { stat in
                ProviderStatRow(stat: stat)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Individual provider stat row
struct ProviderStatRow: View {
    let stat: ProviderStatistics

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(stat.provider.color)
                    .frame(width: 12, height: 12)

                Text(stat.provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(stat.formattedHours)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("(\(stat.formattedPercentage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(stat.provider.color)
                        .frame(width: geometry.size.width * CGFloat(stat.percentage / 100))
                }
            }
            .frame(height: 8)
        }
    }
}

/// Daily bar chart
struct DailyBarChart: View {
    let data: [(date: Date, parentA: Double, parentB: Double, nanny: Double)]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Daily Breakdown")
                .font(.headline)

            Chart(data, id: \.date) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Hours", item.parentA)
                )
                .foregroundStyle(CareProvider.parentA.color)

                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Hours", item.parentB)
                )
                .foregroundStyle(CareProvider.parentB.color)

                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Hours", item.nanny)
                )
                .foregroundStyle(CareProvider.nanny.color)
            }
        }
    }
}

/// Custom date range picker sheet
struct CustomDateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    CareLogSummaryView()
}
