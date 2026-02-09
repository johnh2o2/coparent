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
        .parentA: "Caregiver 1",
        .parentB: "Caregiver 2",
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
        self.currentUser = UserProfileManager.shared.currentUser
    }

    // MARK: - Setup

    /// Initialize and check CloudKit status
    func setup() async {
        isLoading = true

        do {
            try await cloudKit.setup()
            isCloudKitEnabled = cloudKit.isAuthenticated

            let repo = TimeBlockRepository.shared
            if repo.consecutiveFetchFailures > 0 {
                cloudKitStatus = "Queries failing (\(repo.consecutiveFetchFailures)x)"
            } else {
                cloudKitStatus = "Connected"
            }

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
            user.saveLocally()
            UserProfileManager.shared.reload()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Family Sharing

    /// Create a share invitation using zone-wide sharing so all schedule
    /// data (blocks, messages, etc.) is accessible to the co-parent.
    func createShareInvitation() async {
        isLoading = true
        errorMessage = nil

        guard currentUser != nil else {
            errorMessage = "Please create your profile first"
            isLoading = false
            return
        }

        do {
            // Save a Family record with provider names so the recipient can
            // pick up naming conventions. This record lives in the shared zone
            // and will be accessible once the share is accepted.
            let familyRecord = CKRecord(recordType: "Family")
            familyRecord["name"] = "Our Family Schedule"
            let profile = UserProfileManager.shared
            familyRecord["parentAName"] = profile.providerNames[.parentA] ?? "Caregiver 1"
            familyRecord["parentBName"] = profile.providerNames[.parentB] ?? "Caregiver 2"
            familyRecord["nannyName"] = profile.providerNames[.nanny] ?? "Nanny"
            let _ = try await cloudKit.save(familyRecord)

            // Create a zone-wide share — this gives the co-parent access
            // to ALL records in the zone (schedules, messages, etc.)
            let share = try await cloudKit.createZoneShare(title: "Co-Parenting Schedule")

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

            // Update claimed roles in profile manager (exclude current user)
            let profile = UserProfileManager.shared
            var claimed: [UserRole: String] = [:]
            for user in allUsers where user.id != profile.currentUser?.id {
                claimed[user.role] = user.displayName
            }
            profile.claimedRoles = claimed

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

    /// Update provider display name — delegates to UserProfileManager for propagation
    func setProviderName(_ name: String, for provider: CareProvider) {
        providerNames[provider] = name
        UserProfileManager.shared.setProviderName(name, for: provider)
        currentUser = UserProfileManager.shared.currentUser
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

        // Sync provider names from the shared profile manager
        providerNames = UserProfileManager.shared.providerNames
        currentUser = UserProfileManager.shared.currentUser
    }

    // MARK: - Sync

    /// Force a sync with CloudKit
    func forceSync() async {
        isSyncing = true

        do {
            try await cloudKit.setup()
            await loadUserProfile()
            await loadFamilyMembers()

            // Run a diagnostic fetch to exercise the CloudKit query path
            // and check whether queries are working.
            let repo = TimeBlockRepository.shared
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: today)!
            let _ = try await repo.fetchBlocks(from: today, to: weekEnd)

            if repo.consecutiveFetchFailures > 0 {
                cloudKitStatus = "Queries failing (\(repo.consecutiveFetchFailures)x)"
            } else {
                cloudKitStatus = "Connected"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Diagnostics

    var diagnosticContainerID: String { cloudKit.containerIdentifier }
    var diagnosticZoneStatus: String { cloudKit.zoneStatus }
    var diagnosticLastOp: String { cloudKit.lastOperationLog }
    var diagnosticFetchFailures: Int { TimeBlockRepository.shared.consecutiveFetchFailures }
    var diagnosticLastError: String {
        TimeBlockRepository.shared.lastFetchError?.localizedDescription ?? "none"
    }
    var diagnosticCacheCount: Int { TimeBlockRepository.shared.timeBlocks.count }

    /// Run a full diagnostic check
    func runDiagnostics() async -> String {
        var lines: [String] = []
        lines.append("Container: \(cloudKit.containerIdentifier)")
        lines.append("Authenticated: \(cloudKit.isAuthenticated)")

        let zoneHealth = await cloudKit.checkZoneHealth()
        lines.append("Zone: \(zoneHealth)")

        lines.append("Cache: \(TimeBlockRepository.shared.timeBlocks.count) blocks")
        lines.append("Fetch failures: \(TimeBlockRepository.shared.consecutiveFetchFailures)")

        if let err = TimeBlockRepository.shared.lastFetchError {
            lines.append("Last error: \(err)")
        }

        lines.append("Last op: \(cloudKit.lastOperationLog)")

        return lines.joined(separator: "\n")
    }

    /// Save a test TimeBlock, fetch it back, then delete it.
    /// Proves the full CloudKit round-trip works in the current environment.
    func runSaveTest() async -> String {
        var lines: [String] = []
        let testBlock = TimeBlock(
            date: Date(),
            startSlot: 32,
            endSlot: 36,
            provider: .parentA,
            notes: "DIAGNOSTIC TEST — safe to delete"
        )

        // Step 1: Save
        do {
            let record = testBlock.toRecord()
            let saved = try await cloudKit.save(record)
            lines.append("1. SAVE: OK (id: \(saved.recordID.recordName))")

            // Step 2: Fetch
            do {
                let fetched = try await cloudKit.fetch(recordID: saved.recordID)
                if let _ = TimeBlock(from: fetched) {
                    lines.append("2. FETCH: OK — record found and parsed")
                } else {
                    lines.append("2. FETCH: PARTIAL — record found but failed to parse as TimeBlock")
                }
            } catch {
                lines.append("2. FETCH: FAILED — \(error.localizedDescription)")
            }

            // Step 3: Delete
            do {
                try await cloudKit.delete(recordID: saved.recordID)
                lines.append("3. DELETE: OK — test record cleaned up")
            } catch {
                lines.append("3. DELETE: FAILED — \(error.localizedDescription)")
                lines.append("   (test record may remain in CloudKit)")
            }

            // Step 4: Query
            do {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                let results = try await cloudKit.fetchRecords(
                    recordType: TimeBlock.recordType,
                    predicate: NSPredicate(format: "date >= %@ AND date <= %@", today as NSDate, tomorrow as NSDate)
                )
                lines.append("4. QUERY: OK — \(results.count) TimeBlocks for today")
            } catch {
                lines.append("4. QUERY: FAILED — \(error.localizedDescription)")
            }

        } catch {
            lines.append("1. SAVE: FAILED — \(error.localizedDescription)")
            lines.append("   This is the root problem. Data cannot be written to CloudKit Production.")
        }

        lines.append("")
        lines.append("Round-trip \(lines.first?.contains("FAILED") == true ? "FAILED" : "PASSED")")

        return lines.joined(separator: "\n")
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
