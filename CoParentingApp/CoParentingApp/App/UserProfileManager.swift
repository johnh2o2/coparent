import Foundation
import SwiftUI

/// Shared observable singleton that holds the current user identity and provider names.
/// All SwiftUI views subscribing to this object re-render automatically when either property changes.
@Observable
final class UserProfileManager {
    static let shared = UserProfileManager()

    /// The currently logged-in user, or nil if not yet set up.
    var currentUser: User?

    /// Custom display names for each care provider.
    var providerNames: [CareProvider: String] = [
        .parentA: "Caregiver 1",
        .parentB: "Caregiver 2",
        .nanny: "Nanny"
    ]

    /// Roles already claimed by other family members (role → display name of who claimed it).
    var claimedRoles: [UserRole: String] = [:]

    /// Whether the user joined via a CloudKit share link (skip naming step).
    var joinedViaShare: Bool = false

    private init() {
        reload()
    }

    // MARK: - Mutations

    /// Update the current user's display name and/or role, persisting to UserDefaults.
    func updateUser(displayName: String, role: UserRole) {
        let user = User(
            id: currentUser?.id ?? UUID(),
            displayName: displayName,
            role: role,
            cloudKitRecordID: currentUser?.cloudKitRecordID,
            email: currentUser?.email,
            createdAt: currentUser?.createdAt ?? Date()
        )
        user.saveLocally()
        currentUser = user
    }

    /// Update a single provider's display name. If the renamed provider matches
    /// the current user's role, also updates the user's displayName to stay in sync.
    func setProviderName(_ name: String, for provider: CareProvider) {
        providerNames[provider] = name
        persistProviderNames()

        // Keep user identity in sync if renaming the user's own provider
        if let user = currentUser, user.asCareProvider == provider, !name.isEmpty {
            updateUser(displayName: name, role: user.role)
        }
    }

    /// Reload all state from UserDefaults (e.g. after an external change).
    func reload() {
        currentUser = User.loadLocal()

        if let saved = UserDefaults.standard.dictionary(forKey: "providerNames") as? [String: String] {
            for (key, value) in saved {
                if let provider = CareProvider(rawValue: key) {
                    providerNames[provider] = value
                }
            }
        }
    }

    /// Whether provider names have ever been configured by the user.
    var hasConfiguredProviderNames: Bool {
        UserDefaults.standard.dictionary(forKey: "providerNames") != nil
    }

    /// Import provider names and claimed roles from a CloudKit share.
    /// Called after accepting a share invitation.
    func importSharedFamilySettings(providerNames: [CareProvider: String], claimedRoles: [UserRole: String]) {
        // Save provider names locally
        for (provider, name) in providerNames {
            self.providerNames[provider] = name
        }
        persistProviderNames()

        // Store claimed roles
        self.claimedRoles = claimedRoles
        self.joinedViaShare = true
    }

    // MARK: - Private

    private func persistProviderNames() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: providerNames.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(stringKeyed, forKey: "providerNames")
    }
}

// MARK: - Environment Key

private struct UserProfileManagerKey: EnvironmentKey {
    static let defaultValue = UserProfileManager.shared
}

extension EnvironmentValues {
    var userProfile: UserProfileManager {
        get { self[UserProfileManagerKey.self] }
        set { self[UserProfileManagerKey.self] = newValue }
    }
}
