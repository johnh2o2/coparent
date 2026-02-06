import Foundation
import SwiftUI

/// ViewModel for the Home/Dashboard tab — care balance and recent activity.
@Observable
final class DashboardViewModel {
    private let repository: TimeBlockRepository
    private let activityRepository: ScheduleChangeRepository

    var parentAHours: Double = 0
    var parentBHours: Double = 0
    var nannyHours: Double = 0
    var recentActivity: [ScheduleChangeEntry] = []
    var thisWeekBlocks: [TimeBlock] = []

    var isLoading = false

    init(
        repository: TimeBlockRepository = .shared,
        activityRepository: ScheduleChangeRepository = .shared
    ) {
        self.repository = repository
        self.activityRepository = activityRepository
    }

    // MARK: - Loading

    func loadDashboard() async {
        isLoading = true

        async let balanceTask: () = loadYearBalance()
        async let weekTask: () = loadThisWeek()
        async let activityTask: () = loadRecentActivity()

        await balanceTask
        await weekTask
        await activityTask

        isLoading = false
    }

    private func loadYearBalance() async {
        let calendar = Calendar.current
        let today = Date()
        let yearEnd = calendar.date(byAdding: .weekOfYear, value: 52, to: today)!

        do {
            let blocks = try await repository.fetchBlocks(from: today, to: yearEnd)
            let expanded = SummaryViewModel.expandRecurringBlocks(blocks, from: today, to: yearEnd)

            var parentA: Double = 0
            var parentB: Double = 0
            var nanny: Double = 0

            for block in expanded {
                switch block.provider {
                case .parentA: parentA += block.durationHours
                case .parentB: parentB += block.durationHours
                case .nanny:   nanny += block.durationHours
                case .none:    break
                }
            }

            parentAHours = parentA
            parentBHours = parentB
            nannyHours = nanny
        } catch {
            print("[DashboardViewModel] Year balance fetch failed: \(error.localizedDescription)")
        }
    }

    private func loadThisWeek() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

        do {
            let blocks = try await repository.fetchBlocks(from: weekStart, to: weekEnd)
            thisWeekBlocks = CalendarViewModel.expandRecurringBlocks(blocks, from: weekStart, to: weekEnd)
        } catch {
            print("[DashboardViewModel] Week fetch failed: \(error.localizedDescription)")
        }
    }

    private func loadRecentActivity() async {
        recentActivity = Array(await activityRepository.fetchEntries(limit: 3).prefix(3))
    }

    // MARK: - Computed

    var totalHours: Double {
        parentAHours + parentBHours + nannyHours
    }

    var balanceDelta: Double {
        abs(parentAHours - parentBHours)
    }

    var isBalanced: Bool {
        guard totalHours > 0 else { return true }
        let maxParent = max(parentAHours, parentBHours)
        guard maxParent > 0 else { return true }
        return balanceDelta / maxParent < 0.05
    }

    var parentAFraction: Double {
        let parentTotal = parentAHours + parentBHours
        guard parentTotal > 0 else { return 0.5 }
        return parentAHours / parentTotal
    }

    var parentBFraction: Double {
        1.0 - parentAFraction
    }

    var greeting: String {
        if let user = UserProfileManager.shared.currentUser {
            let firstName = user.displayName.components(separatedBy: " ").first ?? user.displayName
            return "Hi \(firstName)"
        }
        return "Hi there"
    }

    var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Preview Support

extension DashboardViewModel {
    static var preview: DashboardViewModel {
        let vm = DashboardViewModel()
        vm.parentAHours = 520
        vm.parentBHours = 488
        vm.nannyHours = 260
        return vm
    }
}
