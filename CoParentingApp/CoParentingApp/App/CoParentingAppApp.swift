import SwiftUI
import CloudKit

/// App delegate to handle CloudKit share acceptance
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            do {
                try await CloudKitService.shared.acceptShare(metadata: metadata)

                // Fetch provider names and claimed roles from the shared data
                if let settings = await CloudKitService.shared.fetchSharedFamilySettings() {
                    await MainActor.run {
                        UserProfileManager.shared.importSharedFamilySettings(
                            providerNames: settings.providerNames,
                            claimedRoles: settings.claimedRoles
                        )
                    }
                }

                await MainActor.run {
                    NotificationCenter.default.post(name: .didAcceptCloudKitShare, object: nil)
                }
            } catch {
                print("Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}

/// Main entry point for the Co-Parenting App
#if !SPM_BUILD
@main
#endif
struct CoParentingAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var dependencies = DependencyContainer.shared
    @State private var userProfile = UserProfileManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.dependencies, dependencies)
                .environment(\.userProfile, userProfile)
                .task {
                    await dependencies.setup()
                }
        }
    }
}
