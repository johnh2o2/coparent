import SwiftUI

/// Main content view — TabView on iPhone, NavigationSplitView on iPad.
struct ContentView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.userProfile) private var userProfile
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab = Tab.home
    @State private var showShareAcceptedAlert = false
    @State private var showIdentityPrompt = false

    // iPad-specific state
    @State private var selectedNavItem: NavItem? = .calendar
    @State private var showAIAssistant = false
    @State private var sharedDashboardVM = DashboardViewModel()
    @State private var sharedCalendarVM = CalendarViewModel()

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
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptCloudKitShare)) { _ in
            if userProfile.currentUser == nil {
                showIdentityPrompt = true
            } else {
                showShareAcceptedAlert = true
            }
        }
        .alert("Share Accepted", isPresented: $showShareAcceptedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've been connected to a shared family schedule. Shared data will now sync automatically.")
        }
    }

    // MARK: - iPhone Layout (existing TabView)

    private var iPhoneLayout: some View {
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
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .home {
                NotificationCenter.default.post(name: .dashboardShouldReload, object: nil)
            }
        }
    }

    // MARK: - iPad Layout (NavigationSplitView)

    private var iPadLayout: some View {
        NavigationSplitView {
            iPadSidebarView(
                selectedNavItem: $selectedNavItem,
                showAIAssistant: $showAIAssistant,
                dashboardViewModel: sharedDashboardVM
            )
        } detail: {
            iPadDetailView
        }
        .task {
            await sharedDashboardVM.loadDashboard()
            await sharedCalendarVM.loadBlocks()
        }
        .sheet(isPresented: $showAIAssistant, onDismiss: {
            Task {
                await sharedDashboardVM.loadDashboard()
                await sharedCalendarVM.loadBlocks()
            }
        }) {
            AIAssistantSheet(calendarViewModel: sharedCalendarVM)
        }
    }

    @ViewBuilder
    private var iPadDetailView: some View {
        // These views each contain their own NavigationStack, so we
        // don't wrap them again — that would hide the sidebar toggle.
        switch selectedNavItem {
        case .calendar:
            CalendarView(sharedViewModel: sharedCalendarVM)
        case .activity:
            ActivityJournalView()
        case .summary:
            CareLogSummaryView()
        case .settings:
            SettingsView()
        case nil:
            CalendarView(sharedViewModel: sharedCalendarVM)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
