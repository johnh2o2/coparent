import SwiftUI
import UIKit

/// Represents who is providing care during a time block
enum CareProvider: String, Codable, CaseIterable, Identifiable {
    case parentA = "parent_a"
    case parentB = "parent_b"
    case nanny = "nanny"
    case none = "none"

    var id: String { rawValue }

    /// Default display name for the provider
    var defaultDisplayName: String {
        switch self {
        case .parentA: return "Parent A"
        case .parentB: return "Parent B"
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
        case .parentA: return Color(red: 0.302, green: 0.478, blue: 0.820) // Blue
        case .parentB: return Color(red: 0.820, green: 0.478, blue: 0.302) // Orange
        case .nanny: return Color(red: 0.478, green: 0.720, blue: 0.478) // Green
        case .none: return Color.gray.opacity(0.3)
        }
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
