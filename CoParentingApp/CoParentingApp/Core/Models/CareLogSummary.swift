import Foundation

/// Summary of care hours over a date range
struct CareLogSummary: Identifiable, Codable, Equatable {
    let id: UUID
    var startDate: Date
    var endDate: Date
    var hoursByProvider: [CareProvider: Double]
    var totalHours: Double
    var dayCount: Int
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        hoursByProvider: [CareProvider: Double] = [:],
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: endDate)
        self.hoursByProvider = hoursByProvider
        self.totalHours = hoursByProvider.values.reduce(0, +)
        self.dayCount = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0 + 1
        self.generatedAt = generatedAt
    }

    /// Percentage of total hours for a provider
    func percentage(for provider: CareProvider) -> Double {
        guard totalHours > 0 else { return 0 }
        return (hoursByProvider[provider] ?? 0) / totalHours * 100
    }

    /// Hours per day average for a provider
    func averageHoursPerDay(for provider: CareProvider) -> Double {
        guard dayCount > 0 else { return 0 }
        return (hoursByProvider[provider] ?? 0) / Double(dayCount)
    }

    /// Date range as formatted string
    var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    /// Create summary from an array of day schedules
    static func generate(from schedules: [DaySchedule]) -> CareLogSummary {
        guard !schedules.isEmpty else {
            return CareLogSummary(startDate: Date(), endDate: Date())
        }

        let sortedSchedules = schedules.sorted { $0.date < $1.date }
        let startDate = sortedSchedules.first!.date
        let endDate = sortedSchedules.last!.date

        var hoursByProvider: [CareProvider: Double] = [:]

        for schedule in schedules {
            for (provider, hours) in schedule.hoursByProvider {
                hoursByProvider[provider, default: 0] += hours
            }
        }

        return CareLogSummary(
            startDate: startDate,
            endDate: endDate,
            hoursByProvider: hoursByProvider
        )
    }
}

// MARK: - Provider Statistics

struct ProviderStatistics: Identifiable {
    let id: CareProvider
    let provider: CareProvider
    let hours: Double
    let percentage: Double
    let averagePerDay: Double

    var formattedHours: String {
        String(format: "%.1f hrs", hours)
    }

    var formattedPercentage: String {
        String(format: "%.0f%%", percentage)
    }

    var formattedAveragePerDay: String {
        String(format: "%.1f hrs/day", averagePerDay)
    }
}

extension CareLogSummary {
    /// Get statistics for all providers
    var providerStatistics: [ProviderStatistics] {
        CareProvider.allCases
            .filter { $0 != .none }
            .map { provider in
                ProviderStatistics(
                    id: provider,
                    provider: provider,
                    hours: hoursByProvider[provider] ?? 0,
                    percentage: percentage(for: provider),
                    averagePerDay: averageHoursPerDay(for: provider)
                )
            }
            .filter { $0.hours > 0 }
    }
}

// MARK: - Care Balance

/// Represents the difference between two caregivers in actionable terms
struct CareBalance {
    let ahead: CareProvider
    let behind: CareProvider
    let differenceHours: Double
    let fullDays: Int
    let remainingHours: Double
    let careWindowHoursPerDay: Double

    /// e.g. "3 days, 2.5 hrs"
    var formattedDifference: String {
        if fullDays > 0 && remainingHours >= 0.25 {
            return "\(fullDays) day\(fullDays == 1 ? "" : "s"), \(String(format: "%.1f", remainingHours)) hrs"
        } else if fullDays > 0 {
            return "\(fullDays) care-day\(fullDays == 1 ? "" : "s")"
        } else {
            return String(format: "%.1f hrs", differenceHours)
        }
    }
}

// MARK: - Sample Data

extension CareLogSummary {
    static var sampleSummary: CareLogSummary {
        let calendar = Calendar.current
        let today = Date()
        let startDate = calendar.date(byAdding: .day, value: -6, to: today)!

        return CareLogSummary(
            startDate: startDate,
            endDate: today,
            hoursByProvider: [
                .parentA: 28.0,
                .parentB: 24.0,
                .nanny: 20.0
            ]
        )
    }
}
