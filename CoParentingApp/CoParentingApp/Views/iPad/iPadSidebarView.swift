import SwiftUI

/// Navigation item for iPad sidebar.
enum NavItem: String, Hashable, CaseIterable {
    case calendar = "Calendar"
    case activity = "Activity"
    case summary = "Summary"
    case settings = "Settings"

    var iconName: String {
        switch self {
        case .calendar: return "calendar"
        case .activity: return "clock.arrow.circlepath"
        case .summary: return "chart.pie"
        case .settings: return "gear"
        }
    }
}

/// iPad sidebar with dashboard cards and navigation links.
struct iPadSidebarView: View {
    @Binding var selectedNavItem: NavItem?
    @Binding var showAIAssistant: Bool
    var dashboardViewModel: DashboardViewModel

    var body: some View {
        List(selection: $selectedNavItem) {
            // Dashboard cards section
            Section {
                YearAtAGlanceCard(viewModel: dashboardViewModel)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowSeparator(.hidden)

                AIEntryCard(showAIAssistant: $showAIAssistant)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)

                if !dashboardViewModel.thisWeekBlocks.isEmpty {
                    ThisWeekStrip(blocks: dashboardViewModel.thisWeekBlocks)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
                        .listRowSeparator(.hidden)
                }
            }

            // Navigation section
            Section("Navigate") {
                ForEach(NavItem.allCases, id: \.self) { item in
                    Label(item.rawValue, systemImage: item.iconName)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Home")
    }
}
