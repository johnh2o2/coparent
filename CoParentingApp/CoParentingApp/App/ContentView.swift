import SwiftUI

/// Main content view with tab navigation
struct ContentView: View {
    @State private var selectedTab = Tab.calendar
    @State private var messagesViewModel = MessagesViewModel()

    enum Tab: String, CaseIterable {
        case calendar = "Calendar"
        case messages = "Messages"
        case summary = "Summary"
        case settings = "Settings"

        var iconName: String {
            switch self {
            case .calendar: return "calendar"
            case .messages: return "message"
            case .summary: return "chart.pie"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarView()
                .tabItem {
                    Label(Tab.calendar.rawValue, systemImage: Tab.calendar.iconName)
                }
                .tag(Tab.calendar)

            MessageThreadListView()
                .tabItem {
                    Label(Tab.messages.rawValue, systemImage: Tab.messages.iconName)
                }
                .tag(Tab.messages)
                .badge(messagesViewModel.totalUnreadCount)

            CareLogSummaryView()
                .tabItem {
                    Label(Tab.summary.rawValue, systemImage: Tab.summary.iconName)
                }
                .tag(Tab.summary)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.iconName)
                }
                .tag(Tab.settings)
        }
        .task {
            await messagesViewModel.loadThreads()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
