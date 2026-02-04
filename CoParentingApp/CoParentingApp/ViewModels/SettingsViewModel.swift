import Foundation
import SwiftUI
import CloudKit

/// ViewModel for settings and user profile
@Observable
final class SettingsViewModel {
    private let cloudKit: CloudKitService
    private let aiService: AIScheduleService

    // Current user
    var currentUser: User?
    var familyMembers: [User] = []

    // CloudKit state
    var isCloudKitEnabled = false
    var cloudKitStatus: String = "Checking..."
    var isSyncing = false

    // AI state
    var anthropicAPIKey: String = ""
    var isAIConfigured: Bool { aiService.isConfigured }

    // Settings
    var notificationsEnabled = true
    var defaultCalendarView: String = "week"
    var careWindowStart: Int = SlotUtility.defaultCareWindowStart
    var careWindowEnd: Int = SlotUtility.defaultCareWindowEnd
    var providerNames: [CareProvider: String] = [
        .parentA: "Parent A",
        .parentB: "Parent B",
        .nanny: "Nanny"
    ]

    var isLoading = false
    var errorMessage: String?

    // Share state
    var shareURL: URL?
    var isShareSheetPresented = false

    init(cloudKit: CloudKitService = .shared, aiService: AIScheduleService = AIScheduleService()) {
        self.cloudKit = cloudKit
        self.aiService = aiService
        self.anthropicAPIKey = AIScheduleService.savedAPIKey ?? ""
    }

    // MARK: - Setup

    /// Initialize and check CloudKit status
    func setup() async {
        isLoading = true

        do {
            try await cloudKit.setup()
            isCloudKitEnabled = cloudKit.isAuthenticated
            cloudKitStatus = "Connected"

            // Try to fetch current user profile
            await loadUserProfile()

        } catch {
            isCloudKitEnabled = false
            cloudKitStatus = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - User Profile

    /// Load current user profile
    func loadUserProfile() async {
        guard cloudKit.isAuthenticated else { return }

        do {
            let predicate = NSPredicate(format: "cloudKitRecordID == %@", cloudKit.currentUserRecordID?.recordName ?? "")
            let records = try await cloudKit.fetchRecords(recordType: User.recordType, predicate: predicate, limit: 1)

            if let record = records.first, let user = User(from: record) {
                currentUser = user
            }
        } catch {
            // User might not exist yet
        }
    }

    /// Create or update user profile
    func saveUserProfile(displayName: String, role: UserRole) async {
        isLoading = true
        errorMessage = nil

        let user = User(
            id: currentUser?.id ?? UUID(),
            displayName: displayName,
            role: role,
            cloudKitRecordID: cloudKit.currentUserRecordID?.recordName
        )

        do {
            let record = user.toRecord()
            let _ = try await cloudKit.save(record)
            currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Family Sharing

    /// Create a share invitation
    func createShareInvitation() async {
        isLoading = true
        errorMessage = nil

        guard let user = currentUser else {
            errorMessage = "Please create your profile first"
            isLoading = false
            return
        }

        do {
            // Create a "family" record to share
            let familyRecord = CKRecord(recordType: "Family")
            familyRecord["name"] = "Our Family Schedule"
            familyRecord["createdBy"] = user.id.uuidString

            let share = try await cloudKit.createShare(for: familyRecord, title: "Co-Parenting Schedule")

            // Get share URL
            shareURL = share.url
            isShareSheetPresented = true

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Load family members (people with access to shared data)
    func loadFamilyMembers() async {
        isLoading = true

        do {
            // Fetch users from shared database
            let sharedRecords = try await cloudKit.fetchSharedRecords(recordType: User.recordType)
            let sharedUsers = sharedRecords.compactMap { User(from: $0) }

            // Fetch users from private database
            let privateRecords = try await cloudKit.fetchRecords(recordType: User.recordType)
            let privateUsers = privateRecords.compactMap { User(from: $0) }

            // Combine and deduplicate
            var allUsers = privateUsers
            for user in sharedUsers {
                if !allUsers.contains(where: { $0.id == user.id }) {
                    allUsers.append(user)
                }
            }

            familyMembers = allUsers

        } catch {
            // Ignore errors, just show what we have
        }

        isLoading = false
    }

    // MARK: - Settings

    /// Save notification preference
    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
    }

    /// Save default calendar view
    func setDefaultCalendarView(_ view: String) {
        defaultCalendarView = view
        UserDefaults.standard.set(view, forKey: "defaultCalendarView")
    }

    /// Update provider display name
    func setProviderName(_ name: String, for provider: CareProvider) {
        providerNames[provider] = name
        // Convert to [String: String] keyed by rawValue for UserDefaults
        let stringKeyed = Dictionary(uniqueKeysWithValues: providerNames.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(stringKeyed, forKey: "providerNames")
    }

    /// Update care window start slot
    func setCareWindowStart(_ slot: Int) {
        careWindowStart = slot
        SlotUtility.setCareWindow(start: slot, end: careWindowEnd)
    }

    /// Update care window end slot
    func setCareWindowEnd(_ slot: Int) {
        careWindowEnd = slot
        SlotUtility.setCareWindow(start: careWindowStart, end: slot)
    }

    /// Reset care window to defaults
    func resetCareWindow() {
        SlotUtility.resetCareWindow()
        careWindowStart = SlotUtility.defaultCareWindowStart
        careWindowEnd = SlotUtility.defaultCareWindowEnd
    }

    /// Save or clear the Anthropic API key
    func saveAnthropicAPIKey() {
        let trimmed = anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            aiService.clearAPIKey()
        } else {
            aiService.saveAPIKey(trimmed)
        }
    }

    /// Load saved settings
    func loadSettings() {
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        defaultCalendarView = UserDefaults.standard.string(forKey: "defaultCalendarView") ?? "week"
        careWindowStart = SlotUtility.careWindowStart
        careWindowEnd = SlotUtility.careWindowEnd

        if let savedNames = UserDefaults.standard.dictionary(forKey: "providerNames") as? [String: String] {
            for (key, value) in savedNames {
                if let provider = CareProvider(rawValue: key) {
                    providerNames[provider] = value
                }
            }
        }
    }

    // MARK: - Sync

    /// Force a sync with CloudKit
    func forceSync() async {
        isSyncing = true

        do {
            try await cloudKit.setup()
            await loadUserProfile()
            await loadFamilyMembers()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncing = false
    }
}

// MARK: - Preview Support

extension SettingsViewModel {
    static var preview: SettingsViewModel {
        let viewModel = SettingsViewModel()
        viewModel.currentUser = User.sampleParentA
        viewModel.familyMembers = [User.sampleParentA, User.sampleParentB, User.sampleNanny]
        viewModel.isCloudKitEnabled = true
        viewModel.cloudKitStatus = "Connected"
        return viewModel
    }
}
