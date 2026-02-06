import SwiftUI

/// Main content view with tab navigation
struct ContentView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.userProfile) private var userProfile
    @State private var selectedTab = Tab.home
    @State private var showShareAcceptedAlert = false
    @State private var showIdentityPrompt = false

    enum Tab: String, CaseIterable {
        case home = "Home"
        case calendar = "Calendar"
        case activity = "Activity"
        case summary = "Summary"
        case settings = "Settings"

        var iconName: String {
            switch self {
            case .home: return "house.fill"
            case .calendar: return "calendar"
            case .activity: return "clock.arrow.circlepath"
            case .summary: return "chart.pie"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label(Tab.home.rawValue, systemImage: Tab.home.iconName)
                }
                .tag(Tab.home)

            CalendarView()
                .tabItem {
                    Label(Tab.calendar.rawValue, systemImage: Tab.calendar.iconName)
                }
                .tag(Tab.calendar)

            ActivityJournalView()
                .tabItem {
                    Label(Tab.activity.rawValue, systemImage: Tab.activity.iconName)
                }
                .tag(Tab.activity)

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
        .onAppear {
            if userProfile.currentUser == nil {
                showIdentityPrompt = true
            }
        }
        .sheet(isPresented: $showIdentityPrompt) {
            ProfileEditorSheet(currentUser: nil, isRequired: true) { name, role in
                userProfile.updateUser(displayName: name, role: role)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .home {
                // Trigger a reload notification so DashboardView refreshes with latest data
                NotificationCenter.default.post(name: .dashboardShouldReload, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptCloudKitShare)) { _ in
            showShareAcceptedAlert = true
        }
        .alert("Share Accepted", isPresented: $showShareAcceptedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've been connected to a shared family schedule. Shared data will now sync automatically.")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
