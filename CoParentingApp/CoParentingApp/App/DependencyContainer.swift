import Foundation
import SwiftUI

/// Dependency injection container for the app
@Observable
final class DependencyContainer {
    static let shared = DependencyContainer()

    // Services
    let cloudKitService: CloudKitService
    let aiService: AIScheduleService
    let voiceService: VoiceInputService

    // Repositories
    let timeBlockRepository: TimeBlockRepository
    let messageRepository: MessageRepository

    private init() {
        // Initialize services
        cloudKitService = CloudKitService.shared
        aiService = AIScheduleService()
        voiceService = VoiceInputService()

        // Initialize repositories
        timeBlockRepository = TimeBlockRepository(cloudKit: cloudKitService)
        messageRepository = MessageRepository(cloudKit: cloudKitService)
    }

    /// The locally persisted current user identity
    var currentUser: User? { UserProfileManager.shared.currentUser }

    // MARK: - View Model Factories

    /// Create a CalendarViewModel
    func makeCalendarViewModel() -> CalendarViewModel {
        CalendarViewModel(repository: timeBlockRepository, aiService: aiService)
    }

    /// Create a MessagesViewModel
    func makeMessagesViewModel() -> MessagesViewModel {
        MessagesViewModel(repository: messageRepository, aiService: aiService)
    }

    /// Create a SummaryViewModel
    func makeSummaryViewModel() -> SummaryViewModel {
        SummaryViewModel(repository: timeBlockRepository)
    }

    /// Create a SettingsViewModel
    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(cloudKit: cloudKitService, aiService: aiService)
    }

    // MARK: - App Setup

    /// Whether CloudKit setup has completed
    var isCloudKitReady = false

    /// Initialize the app services
    func setup() async {
        // Set up CloudKit — don't load sample data, just wait for real data
        do {
            try await cloudKitService.setup()
            try await cloudKitService.setupSubscriptions()
            print("[DependencyContainer] CloudKit setup complete, authenticated: \(cloudKitService.isAuthenticated)")

            isCloudKitReady = true

            // Fetch initial data now that CloudKit is ready
            if cloudKitService.isAuthenticated {
                let calendar = Calendar.current
                let today = Date()
                let rangeStart = calendar.date(byAdding: .month, value: -1, to: today)!
                let rangeEnd = calendar.date(byAdding: .month, value: 2, to: today)!

                let blocks = try await timeBlockRepository.fetchBlocks(from: rangeStart, to: rangeEnd)
                print("[DependencyContainer] Initial fetch got \(blocks.count) blocks")

                do {
                    let threads = try await messageRepository.fetchThreads()
                    print("[DependencyContainer] Initial fetch got \(threads.count) message threads")
                } catch {
                    print("[DependencyContainer] Message fetch failed (non-fatal): \(error.localizedDescription)")
                }
            }
        } catch {
            print("[DependencyContainer] CloudKit setup failed: \(error)")
            isCloudKitReady = true  // Still mark as ready so UI isn't stuck
        }
    }
}

// MARK: - Environment Key

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue = DependencyContainer.shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - Preview Support

extension DependencyContainer {
    /// Create a container with mock data for previews
    static var preview: DependencyContainer {
        let container = DependencyContainer.shared

        // Load sample data
        container.timeBlockRepository.loadSampleData()
        container.messageRepository.loadSampleData()

        return container
    }
}
