import SwiftUI

/// Settings and profile view
struct SettingsView: View {
    @Environment(\.userProfile) private var userProfile
    @State private var viewModel = SettingsViewModel()
    @State private var showingProfileEditor = false
    @State private var diagnosticReport: String?

    var body: some View {
        NavigationStack {
            Form {
                // Profile section
                Section {
                    if let user = userProfile.currentUser {
                        HStack(spacing: 16) {
                            // Avatar with gradient fill
                            ZStack {
                                Circle()
                                    .fill(user.asCareProvider.gradient)
                                    .frame(width: 60, height: 60)

                                Text(user.avatarInitials)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)

                                Text(user.role.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                showingProfileEditor = true
                            } label: {
                                Text("Edit")
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            showingProfileEditor = true
                        } label: {
                            Label("Create Profile", systemImage: "person.badge.plus")
                        }
                    }
                } header: {
                    Text("Profile")
                }

                // CloudKit section
                Section {
                    HStack {
                        Label("iCloud Sync", systemImage: "icloud")
                        Spacer()
                        if viewModel.isSyncing {
                            ProgressView()
                        } else {
                            Text(viewModel.cloudKitStatus)
                                .foregroundStyle(viewModel.isCloudKitEnabled ? .green : .secondary)
                        }
                    }

                    Button {
                        Task {
                            await viewModel.forceSync()
                        }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.isSyncing)
                } header: {
                    Text("Sync")
                }

                // Family section
                Section {
                    Button {
                        Task {
                            await viewModel.createShareInvitation()
                        }
                    } label: {
                        Label("Invite Co-Parent", systemImage: "person.badge.plus")
                    }
                    .disabled(!viewModel.isCloudKitEnabled)

                    ForEach(viewModel.familyMembers) { member in
                        FamilyMemberRow(user: member)
                    }
                } header: {
                    Text("Family")
                } footer: {
                    Text("Invite your co-parent to share schedules and messages.")
                }

                // Provider names section
                Section {
                    ForEach(Array(userProfile.providerNames.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { provider in
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(provider.color)
                                .frame(width: 16, height: 16)

                            TextField(
                                provider.defaultDisplayName,
                                text: Binding(
                                    get: { userProfile.providerNames[provider] ?? provider.defaultDisplayName },
                                    set: { userProfile.setProviderName($0, for: provider) }
                                )
                            )
                        }
                    }
                } header: {
                    Text("Provider Names")
                } footer: {
                    Text("Customize the display names for each care provider. Changes update your identity everywhere.")
                }

                // AI Assistant section
                Section {
                    HStack {
                        Label("Status", systemImage: "wand.and.stars")
                        Spacer()
                        Text(viewModel.isAIConfigured ? "Connected" : "Not Configured")
                            .foregroundStyle(viewModel.isAIConfigured ? .green : .secondary)
                    }

                    SecureField("sk-ant-...", text: $viewModel.anthropicAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            viewModel.saveAnthropicAPIKey()
                        }

                    Button {
                        viewModel.saveAnthropicAPIKey()
                    } label: {
                        Label("Save Key", systemImage: "checkmark.circle")
                    }
                    .disabled(viewModel.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("AI Assistant")
                } footer: {
                    Text("Enter your Anthropic API key to enable AI-powered schedule commands. Get one at console.anthropic.com.")
                }

                // AI Usage section
                AIUsageSection()

                // AI History section
                Section {
                    NavigationLink {
                        AIHistoryView()
                    } label: {
                        Label("AI History", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("AI History")
                } footer: {
                    Text("View past AI assistant interactions, commands, and results.")
                }

                // Notifications section
                Section {
                    Toggle("Schedule Changes", isOn: $viewModel.notificationsEnabled)
                        .onChange(of: viewModel.notificationsEnabled) { _, newValue in
                            viewModel.setNotificationsEnabled(newValue)
                        }
                } header: {
                    Text("Notifications")
                }

                // Calendar defaults section
                Section {
                    Picker("Default View", selection: $viewModel.defaultCalendarView) {
                        Text("Day").tag("day")
                        Text("Week").tag("week")
                        Text("Month").tag("month")
                    }
                    .onChange(of: viewModel.defaultCalendarView) { _, newValue in
                        viewModel.setDefaultCalendarView(newValue)
                    }
                } header: {
                    Text("Calendar")
                }

                // Care Time Window section
                Section {
                    Picker("Earliest Start", selection: Binding(
                        get: { viewModel.careWindowStart },
                        set: { viewModel.setCareWindowStart($0) }
                    )) {
                        // 5:00 AM (slot 20) to 12:00 PM (slot 48)
                        ForEach(Array(stride(from: 20, through: 48, by: 1)), id: \.self) { slot in
                            Text(SlotUtility.formatSlot(slot)).tag(slot)
                        }
                    }

                    Picker("Latest End", selection: Binding(
                        get: { viewModel.careWindowEnd },
                        set: { viewModel.setCareWindowEnd($0) }
                    )) {
                        // 4:00 PM (slot 64) to 11:00 PM (slot 92)
                        ForEach(Array(stride(from: 64, through: 92, by: 1)), id: \.self) { slot in
                            Text(SlotUtility.formatSlot(slot)).tag(slot)
                        }
                    }

                    HStack {
                        Text("Current Window")
                        Spacer()
                        Text("\(SlotUtility.formatSlot(viewModel.careWindowStart)) – \(SlotUtility.formatSlot(viewModel.careWindowEnd))")
                            .foregroundStyle(.secondary)
                    }

                    Button("Reset to Default") {
                        viewModel.resetCareWindow()
                    }
                } header: {
                    Text("Care Time Window")
                } footer: {
                    Text("Blocks outside this window are treated as sleep/personal time and won't be scheduled.")
                }

                // Diagnostics section
                Section {
                    HStack {
                        Text("Container")
                        Spacer()
                        Text(viewModel.diagnosticContainerID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    HStack {
                        Text("Zone")
                        Spacer()
                        Text(viewModel.diagnosticZoneStatus)
                            .font(.caption)
                            .foregroundStyle(viewModel.diagnosticZoneStatus.hasPrefix("Ready") || viewModel.diagnosticZoneStatus.contains("OK") ? .green : .orange)
                            .lineLimit(2)
                    }

                    HStack {
                        Text("Local Cache")
                        Spacer()
                        Text("\(viewModel.diagnosticCacheCount) blocks")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Fetch Failures")
                        Spacer()
                        Text("\(viewModel.diagnosticFetchFailures)")
                            .foregroundStyle(viewModel.diagnosticFetchFailures > 0 ? .red : .green)
                    }

                    if viewModel.diagnosticFetchFailures > 0 {
                        HStack {
                            Text("Last Error")
                            Spacer()
                            Text(viewModel.diagnosticLastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }

                    if !viewModel.diagnosticLastOp.isEmpty {
                        HStack {
                            Text("Last Op")
                            Spacer()
                            Text(viewModel.diagnosticLastOp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }

                    Button {
                        Task {
                            diagnosticReport = await viewModel.runDiagnostics()
                        }
                    } label: {
                        Label("Run Diagnostics", systemImage: "stethoscope")
                    }

                    if let report = diagnosticReport {
                        Text(report)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Debug info for troubleshooting CloudKit sync issues.")
                }

                // About section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://example.com/support")!) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingProfileEditor) {
                ProfileEditorSheet(
                    currentUser: userProfile.currentUser,
                    onSave: { name, role in
                        userProfile.updateUser(displayName: name, role: role)
                        Task {
                            await viewModel.saveUserProfile(displayName: name, role: role)
                        }
                    }
                )
            }
            .sheet(isPresented: $viewModel.isShareSheetPresented) {
                if let url = viewModel.shareURL {
                    ShareSheet(items: [url])
                }
            }
            .task {
                await viewModel.setup()
                viewModel.loadSettings()
            }
        }
    }
}

/// Row showing a family member
struct FamilyMemberRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(user.asCareProvider.color.opacity(0.2))
                    .frame(width: 40, height: 40)

                Text(user.avatarInitials)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(user.asCareProvider.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline)

                Text(user.role.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Profile editor sheet — 2-step setup flow:
/// Step 1: Name the caregivers (only if never configured)
/// Step 2: Pick which caregiver you are
struct ProfileEditorSheet: View {
    let currentUser: User?
    let isRequired: Bool
    let onSave: (String, UserRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.userProfile) private var userProfile

    // Step tracking
    @State private var step: SetupStep

    // Step 1 state — caregiver names
    @State private var parentAName: String
    @State private var parentBName: String
    @State private var nannyName: String

    // Step 2 state — identity pick
    @State private var selectedRole: UserRole?

    enum SetupStep {
        case nameProviders
        case pickIdentity
    }

    init(currentUser: User?, isRequired: Bool = false, onSave: @escaping (String, UserRole) -> Void) {
        self.currentUser = currentUser
        self.isRequired = isRequired
        self.onSave = onSave

        let profile = UserProfileManager.shared
        let storedA = profile.providerNames[.parentA]
        let storedB = profile.providerNames[.parentB]
        _parentAName = State(initialValue: profile.hasConfiguredProviderNames ? (storedA ?? "") : "")
        _parentBName = State(initialValue: profile.hasConfiguredProviderNames ? (storedB ?? "") : "")
        _nannyName = State(initialValue: profile.providerNames[.nanny] ?? "")

        // Skip step 1 if provider names were already configured, joined via share, or editing existing user
        if profile.hasConfiguredProviderNames || profile.joinedViaShare || currentUser != nil {
            _step = State(initialValue: .pickIdentity)
        } else {
            _step = State(initialValue: .nameProviders)
        }

        _selectedRole = State(initialValue: currentUser?.role)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .nameProviders:
                    nameProvidersView
                case .pickIdentity:
                    pickIdentityView
                }
            }
            .navigationTitle(isRequired ? "Set Up Profile" : (currentUser == nil ? "Create Profile" : "Edit Profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isRequired || step == .pickIdentity {
                    ToolbarItem(placement: .cancellationAction) {
                        if step == .pickIdentity && !userProfile.hasConfiguredProviderNames {
                            Button("Back") {
                                withAnimation { step = .nameProviders }
                            }
                        } else if !isRequired {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isRequired)
    }

    // MARK: - Step 1: Name the caregivers

    private var nameProvidersView: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Text("Mara-Log-O")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)

                    Text("Who are the caregivers?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(CareProvider.parentA.color)
                        .frame(width: 16, height: 16)
                    TextField("First caregiver name", text: $parentAName)
                }
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(CareProvider.parentB.color)
                        .frame(width: 16, height: 16)
                    TextField("Second caregiver name", text: $parentBName)
                }
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(CareProvider.nanny.color)
                        .frame(width: 16, height: 16)
                    TextField("Nanny (optional)", text: $nannyName)
                }
            } header: {
                Text("Caregiver Names")
            } footer: {
                Text("Enter the names of everyone who helps with care. You can change these later in Settings.")
            }

            Section {
                Button {
                    saveProviderNames()
                    withAnimation { step = .pickIdentity }
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(parentAName.trimmingCharacters(in: .whitespaces).isEmpty &&
                          parentBName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Step 2: Pick which caregiver you are

    private var pickIdentityView: some View {
        Form {
            if isRequired {
                Section {
                    VStack(spacing: 8) {
                        Text("Mara-Log-O")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor)

                        Text("Which one are you?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }

            Section {
                caregiverOption(role: .parentA, provider: .parentA)
                caregiverOption(role: .parentB, provider: .parentB)
                if !effectiveNannyName.isEmpty {
                    caregiverOption(role: .caregiver, provider: .nanny)
                }
            } header: {
                Text("Select Your Identity")
            } footer: {
                if userProfile.claimedRoles.isEmpty {
                    Text("Your schedule color and display name will match your selection.")
                } else {
                    Text("Identities already claimed by family members are locked. Your schedule color and display name will match your selection.")
                }
            }

            if selectedRole != nil {
                Section {
                    Button {
                        saveIdentity()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Done")
                        }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func caregiverOption(role: UserRole, provider: CareProvider) -> some View {
        let name = effectiveName(for: provider)
        let claimedBy = userProfile.claimedRoles[role]
        let isClaimed = claimedBy != nil && currentUser?.role != role

        return Button {
            if !isClaimed {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedRole = role
                }
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isClaimed ? AnyShapeStyle(Color(.systemGray4)) : AnyShapeStyle(provider.gradient))
                        .frame(width: 44, height: 44)
                    Text(User.initials(from: name))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isClaimed ? .secondary : .white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isClaimed ? .secondary : .primary)
                    if isClaimed, let claimedBy {
                        Text("Taken by \(claimedBy)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(role.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isClaimed {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if selectedRole == role {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(provider.color)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isClaimed)
    }

    // MARK: - Helpers

    private func effectiveName(for provider: CareProvider) -> String {
        switch provider {
        case .parentA: return parentAName.isEmpty ? userProfile.providerNames[.parentA] ?? "Caregiver 1" : parentAName
        case .parentB: return parentBName.isEmpty ? userProfile.providerNames[.parentB] ?? "Caregiver 2" : parentBName
        case .nanny: return effectiveNannyName
        default: return provider.defaultDisplayName
        }
    }

    private var effectiveNannyName: String {
        nannyName.isEmpty ? (userProfile.providerNames[.nanny] ?? "") : nannyName
    }

    private func saveProviderNames() {
        let trimA = parentAName.trimmingCharacters(in: .whitespaces)
        let trimB = parentBName.trimmingCharacters(in: .whitespaces)
        let trimN = nannyName.trimmingCharacters(in: .whitespaces)

        if !trimA.isEmpty { userProfile.setProviderName(trimA, for: .parentA) }
        if !trimB.isEmpty { userProfile.setProviderName(trimB, for: .parentB) }
        if !trimN.isEmpty { userProfile.setProviderName(trimN, for: .nanny) }
    }

    private func saveIdentity() {
        guard let role = selectedRole else { return }
        let provider: CareProvider
        switch role {
        case .parentA: provider = .parentA
        case .parentB: provider = .parentB
        case .caregiver: provider = .nanny
        }
        let name = effectiveName(for: provider)
        onSave(name, role)
    }
}

/// Share sheet for UIKit sharing
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Section displaying cumulative AI API usage and estimated cost
struct AIUsageSection: View {
    private var tracker: APIUsageTracker { APIUsageTracker.shared }
    @State private var showingResetConfirm = false

    var body: some View {
        Section {
            HStack {
                Label("Requests", systemImage: "arrow.up.arrow.down")
                Spacer()
                Text("\(tracker.totalRequests)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Input Tokens", systemImage: "arrow.up.circle")
                Spacer()
                Text(formattedTokens(tracker.totalInputTokens))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Output Tokens", systemImage: "arrow.down.circle")
                Spacer()
                Text(formattedTokens(tracker.totalOutputTokens))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Estimated Cost", systemImage: "dollarsign.circle")
                Spacer()
                Text(formattedCost(tracker.estimatedCost))
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
            }

            Button(role: .destructive) {
                showingResetConfirm = true
            } label: {
                Label("Reset Usage Data", systemImage: "arrow.counterclockwise")
            }
            .confirmationDialog("Reset usage data?", isPresented: $showingResetConfirm) {
                Button("Reset", role: .destructive) {
                    tracker.reset()
                }
            } message: {
                Text("This will clear all tracked token counts and cost estimates.")
            }
        } header: {
            Text("AI Usage")
        } footer: {
            Text("Based on Claude Sonnet 4.5 pricing: $3/MTok input, $15/MTok output.")
        }
    }

    private func formattedTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formattedCost(_ cost: Double) -> String {
        if cost < 0.01 && cost > 0 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
