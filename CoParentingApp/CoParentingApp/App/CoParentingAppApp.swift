import SwiftUI

/// Main entry point for the Co-Parenting App
#if !SPM_BUILD
@main
#endif
struct CoParentingAppApp: App {
    @State private var dependencies = DependencyContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.dependencies, dependencies)
                .task {
                    await dependencies.setup()
                }
        }
    }
}
