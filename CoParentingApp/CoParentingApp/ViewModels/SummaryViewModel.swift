import Foundation
import SwiftUI

/// ViewModel for care log summary and statistics
@Observable
final class SummaryViewModel {
    private let repository: TimeBlockRepository

    // State
    var startDate: Date
    var endDate: Date
    var summary: CareLogSummary?
    var dailyBreakdown: [DaySchedule] = []

    var isLoading = false
    var errorMessage: String?

    // Predefined date ranges
    enum DateRange: String, CaseIterable, Identifiable {
        case thisWeek = "This Week"
        case lastWeek = "Last Week"
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case custom = "Custom"

        var id: String { rawValue }
    }

    var selectedRange: DateRange = .thisWeek {
        didSet {
            updateDateRange()
        }
    }

    init(repository: TimeBlockRepository = .shared) {
        self.repository = repository

        // Default to this week
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        self.startDate = weekStart
        self.endDate = calendar.date(byAdding: .day, value: 6, to: weekStart)!
    }

    // MARK: - Data Loading

    /// Load summary for the selected date range
    func loadSummary() async {
        isLoading = true
        errorMessage = nil

        do {
            let blocks = try await repository.fetchBlocks(from: startDate, to: endDate)
            let expanded = Self.expandRecurringBlocks(blocks, from: startDate, to: endDate)

            // Group by day
            let calendar = Calendar.current
            var schedulesByDate: [Date: DaySchedule] = [:]

            for block in expanded {
                let dayStart = calendar.startOfDay(for: block.date)
                if schedulesByDate[dayStart] == nil {
                    schedulesByDate[dayStart] = DaySchedule(date: dayStart)
                }
                schedulesByDate[dayStart]?.blocks.append(block)
            }

            dailyBreakdown = schedulesByDate.values.sorted { $0.date < $1.date }

            // Generate summary
            summary = CareLogSummary.generate(from: dailyBreakdown)

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Expand recurring blocks into concrete instances for a date range.
    /// Non-recurring blocks pass through as-is.
    static func expandRecurringBlocks(_ blocks: [TimeBlock], from startDate: Date, to endDate: Date) -> [TimeBlock] {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: startDate)
        let rangeEnd = calendar.startOfDay(for: endDate)
        var result: [TimeBlock] = []

        for block in blocks {
            if block.recurrenceType == .none {
                // Non-recurring: include if in range
                let blockDay = calendar.startOfDay(for: block.date)
                if blockDay >= rangeStart && blockDay <= rangeEnd {
                    result.append(block)
                }
                continue
            }

            // Recurring: generate instances within the range
            let effectiveEnd: Date
            if let recEnd = block.recurrenceEndDate {
                effectiveEnd = min(calendar.startOfDay(for: recEnd), rangeEnd)
            } else {
                effectiveEnd = rangeEnd
            }

            var current = calendar.startOfDay(for: block.date)
            // Advance to the first occurrence at or after rangeStart
            while current < rangeStart {
                guard let next = Self.nextOccurrence(after: current, type: block.recurrenceType, calendar: calendar) else { break }
                current = next
            }

            while current <= effectiveEnd {
                if block.matchesRecurrence(on: current) {
                    var instance = block
                    instance.date = current
                    result.append(instance)
                }
                guard let next = Self.nextOccurrence(after: current, type: block.recurrenceType, calendar: calendar) else { break }
                current = next
            }
        }

        return result
    }

    private static func nextOccurrence(after date: Date, type: RecurrenceType, calendar: Calendar) -> Date? {
        switch type {
        case .everyDay:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .everyWeek:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .everyMonth:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .everyYear:
            return calendar.date(byAdding: .year, value: 1, to: date)
        case .none:
            return nil
        }
    }

    /// Refresh data
    func refresh() async {
        await loadSummary()
    }

    // MARK: - Date Range

    private func updateDateRange() {
        let calendar = Calendar.current
        let today = Date()

        switch selectedRange {
        case .thisWeek:
            startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            endDate = calendar.date(byAdding: .day, value: 6, to: startDate)!

        case .lastWeek:
            let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
            endDate = calendar.date(byAdding: .day, value: 6, to: startDate)!

        case .thisMonth:
            startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate)!

        case .lastMonth:
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            startDate = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
            endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate)!

        case .custom:
            // Keep current dates, let user pick
            break
        }

        Task {
            await loadSummary()
        }
    }

    /// Set custom date range
    func setCustomRange(start: Date, end: Date) {
        selectedRange = .custom
        startDate = start
        endDate = end
        Task {
            await loadSummary()
        }
    }

    // MARK: - Computed Properties

    /// Provider statistics from summary
    var providerStats: [ProviderStatistics] {
        summary?.providerStatistics ?? []
    }

    /// Total hours in the period
    var totalHours: Double {
        summary?.totalHours ?? 0
    }

    /// Formatted date range string
    var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    /// Number of days in range
    var dayCount: Int {
        let calendar = Calendar.current
        return (calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1
    }

    /// Average hours per day
    var averageHoursPerDay: Double {
        guard dayCount > 0 else { return 0 }
        return totalHours / Double(dayCount)
    }
}

// MARK: - Chart Data

extension SummaryViewModel {
    /// Data for pie chart
    var pieChartData: [(provider: CareProvider, hours: Double, color: Color)] {
        providerStats.map { stat in
            (stat.provider, stat.hours, stat.provider.color)
        }
    }

    /// Data for bar chart (daily breakdown)
    var barChartData: [(date: Date, parentA: Double, parentB: Double, nanny: Double)] {
        dailyBreakdown.map { schedule in
            let hours = schedule.hoursByProvider
            return (
                schedule.date,
                hours[.parentA] ?? 0,
                hours[.parentB] ?? 0,
                hours[.nanny] ?? 0
            )
        }
    }
}

// MARK: - Preview Support

extension SummaryViewModel {
    static var preview: SummaryViewModel {
        let viewModel = SummaryViewModel()
        viewModel.summary = CareLogSummary.sampleSummary

        // Create sample daily breakdown
        let calendar = Calendar.current
        let today = Date()

        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                viewModel.dailyBreakdown.append(DaySchedule.sampleSchedule(for: date))
            }
        }

        viewModel.dailyBreakdown.sort { $0.date < $1.date }

        return viewModel
    }
}
