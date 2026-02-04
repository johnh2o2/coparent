import Foundation
import SwiftUI

// MARK: - Date Extensions

extension Date {
    /// Start of the day for this date
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// End of the day for this date
    var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
    }

    /// Check if this date is the same day as another
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Format date as short string
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Format time as short string
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Format as relative date (Today, Yesterday, etc.)
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Get the weekday name
    var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }

    /// Get a short weekday name
    var shortWeekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }
}

// MARK: - Array Extensions

extension Array where Element == TimeBlock {
    /// Sort blocks by start time
    var sortedByStartTime: [TimeBlock] {
        sorted { $0.startSlot < $1.startSlot }
    }

    /// Filter blocks for a specific date
    func blocks(for date: Date) -> [TimeBlock] {
        filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// Filter blocks for a specific provider
    func blocks(for provider: CareProvider) -> [TimeBlock] {
        filter { $0.provider == provider }
    }

    /// Total hours for all blocks
    var totalHours: Double {
        reduce(0) { $0 + $1.durationHours }
    }
}

// MARK: - Color Extensions

extension Color {
    /// Create a lighter version of the color
    func lighter(by amount: Double = 0.2) -> Color {
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(UIColor(
            hue: hue,
            saturation: max(0, saturation - CGFloat(amount)),
            brightness: min(1, brightness + CGFloat(amount)),
            alpha: alpha
        ))
    }

    /// Create a darker version of the color
    func darker(by amount: Double = 0.2) -> Color {
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(UIColor(
            hue: hue,
            saturation: min(1, saturation + CGFloat(amount)),
            brightness: max(0, brightness - CGFloat(amount)),
            alpha: alpha
        ))
    }
}

// MARK: - String Extensions

extension String {
    /// Truncate string to a maximum length with ellipsis
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength {
            return self
        }
        return String(prefix(maxLength - 3)) + "..."
    }
}

// MARK: - View Extensions

extension View {
    /// Apply a corner radius to specific corners
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

/// Shape for specific corner rounding
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
