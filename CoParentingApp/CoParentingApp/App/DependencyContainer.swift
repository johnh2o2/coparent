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

    /// Initialize the app services
    func setup() async {
        // Load local sample data immediately so views have content
        timeBlockRepository.loadSampleData()
        messageRepository.loadSampleData()

        // Attempt CloudKit in background — don't block the UI
        Task.detached(priority: .utility) { [cloudKitService] in
            do {
                try await cloudKitService.setup()
                try await cloudKitService.setupSubscriptions()
            } catch {
                print("CloudKit setup failed (using local storage): \(error)")
            }
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
