import SwiftUI

/// Settings and profile view
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showingProfileEditor = false

    var body: some View {
        NavigationStack {
            Form {
                // Profile section
                Section {
                    if let user = viewModel.currentUser {
                        HStack(spacing: 16) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(user.asCareProvider.color)
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
                    ForEach(Array(viewModel.providerNames.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { provider in
                        HStack {
                            Circle()
                                .fill(provider.color)
                                .frame(width: 12, height: 12)

                            TextField(
                                provider.displayName,
                                text: Binding(
                                    get: { viewModel.providerNames[provider] ?? provider.displayName },
                                    set: { viewModel.setProviderName($0, for: provider) }
                                )
                            )
                        }
                    }
                } header: {
                    Text("Provider Names")
                } footer: {
                    Text("Customize the display names for each care provider.")
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
                    currentUser: viewModel.currentUser,
                    onSave: { name, role in
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

/// Profile editor sheet
struct ProfileEditorSheet: View {
    let currentUser: User?
    let onSave: (String, UserRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var selectedRole: UserRole

    init(currentUser: User?, onSave: @escaping (String, UserRole) -> Void) {
        self.currentUser = currentUser
        self.onSave = onSave
        _displayName = State(initialValue: currentUser?.displayName ?? "")
        _selectedRole = State(initialValue: currentUser?.role ?? .parentA)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Display Name", text: $displayName)
                }

                Section("Role") {
                    Picker("Role", selection: $selectedRole) {
                        ForEach(UserRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle(currentUser == nil ? "Create Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(displayName, selectedRole)
                        dismiss()
                    }
                    .disabled(displayName.isEmpty)
                }
            }
        }
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
