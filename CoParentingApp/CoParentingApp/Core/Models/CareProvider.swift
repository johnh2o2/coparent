import SwiftUI
import UIKit

/// Represents who is providing care during a time block
enum CareProvider: String, Codable, CaseIterable, Identifiable {
    case parentA = "parent_a"
    case parentB = "parent_b"
    case nanny = "nanny"
    case none = "none"

    var id: String { rawValue }

    /// Default display name for the provider (used only before names are configured)
    var defaultDisplayName: String {
        switch self {
        case .parentA: return "Caregiver 1"
        case .parentB: return "Caregiver 2"
        case .nanny: return "Nanny"
        case .none: return "Unassigned"
        }
    }

    /// Display name, using user-customized name from Settings if available
    var displayName: String {
        if self == .none { return defaultDisplayName }
        if let saved = UserDefaults.standard.dictionary(forKey: "providerNames") as? [String: String],
           let custom = saved[rawValue], !custom.isEmpty {
            return custom
        }
        return defaultDisplayName
    }

    /// Color used to display this provider's time blocks
    var color: Color {
        switch self {
        case .parentA: return Color(red: 0.35, green: 0.34, blue: 0.84)  // Soft indigo — twilight sky
        case .parentB: return Color(red: 0.90, green: 0.58, blue: 0.22)  // Warm amber — sunlit earth
        case .nanny: return Color(red: 0.42, green: 0.68, blue: 0.57)    // Soft sage — foliage
        case .none: return Color.gray.opacity(0.3)
        }
    }

    /// Light tint for card backgrounds and row highlights (12% opacity)
    var lightColor: Color {
        color.opacity(0.12)
    }

    /// Subtle vertical gradient for event fills and profile avatars
    var gradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// UIColor version for UIKit integration
    var uiColor: UIColor {
        UIColor(color)
    }

    /// Icon name for SF Symbols
    var iconName: String {
        switch self {
        case .parentA: return "person.fill"
        case .parentB: return "person.fill"
        case .nanny: return "person.badge.clock.fill"
        case .none: return "questionmark.circle"
        }
    }
}
