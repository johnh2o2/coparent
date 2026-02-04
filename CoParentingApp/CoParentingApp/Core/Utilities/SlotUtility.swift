import Foundation

/// Utility for converting between 15-minute time slots and actual times
/// Each day has 96 slots (0-95), each representing 15 minutes
/// Slot 0 = 00:00, Slot 32 = 08:00, Slot 72 = 18:00
enum SlotUtility {
    /// Number of slots per day
    static let slotsPerDay = 96

    /// Minutes per slot
    static let minutesPerSlot = 15

    // MARK: - Time to Slot Conversion

    /// Convert a time (hour, minute) to a slot number
    static func slot(hour: Int, minute: Int) -> Int {
        let totalMinutes = hour * 60 + minute
        return totalMinutes / minutesPerSlot
    }

    /// Convert a Date to a slot number (uses only the time component)
    static func slot(from date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return slot(hour: hour, minute: minute)
    }

    /// Round a Date to the nearest 15-minute slot
    static func roundedSlot(from date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let roundedMinute = ((minute + 7) / 15) * 15
        let adjustedHour = hour + (roundedMinute / 60)
        let finalMinute = roundedMinute % 60
        return slot(hour: adjustedHour, minute: finalMinute)
    }

    // MARK: - Slot to Time Conversion

    /// Convert a slot to hour and minute components
    static func time(for slot: Int) -> (hour: Int, minute: Int) {
        let clampedSlot = max(0, min(slotsPerDay, slot))
        let totalMinutes = clampedSlot * minutesPerSlot
        let hour = totalMinutes / 60
        let minute = totalMinutes % 60
        return (hour, minute)
    }

    /// Convert a slot to a Date on a given day
    static func dateTime(for slot: Int, on date: Date) -> Date {
        let calendar = Calendar.current
        let (hour, minute) = time(for: slot)
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: startOfDay) ?? startOfDay
    }

    // MARK: - Formatting

    /// Format a slot as a time string (e.g., "8:00 AM")
    static func formatSlot(_ slot: Int, style: DateFormatter.Style = .short) -> String {
        let (hour, minute) = time(for: slot)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = style

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }

        // Fallback to manual formatting
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let period = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    /// Format a slot range as a time range string (e.g., "8:00 AM - 12:00 PM")
    static func formatSlotRange(start: Int, end: Int) -> String {
        "\(formatSlot(start)) - \(formatSlot(end))"
    }

    // MARK: - Validation

    /// Check if a slot is valid (0-95)
    static func isValidSlot(_ slot: Int) -> Bool {
        slot >= 0 && slot <= slotsPerDay
    }

    /// Check if a slot range is valid
    static func isValidRange(start: Int, end: Int) -> Bool {
        isValidSlot(start) && isValidSlot(end) && start < end
    }

    // MARK: - Duration Calculation

    /// Calculate duration in minutes between two slots
    static func durationMinutes(start: Int, end: Int) -> Int {
        (end - start) * minutesPerSlot
    }

    /// Calculate duration in hours between two slots
    static func durationHours(start: Int, end: Int) -> Double {
        Double(durationMinutes(start: start, end: end)) / 60.0
    }

    // MARK: - Common Slot Values

    /// Midnight (start of day)
    static let midnight = 0

    /// 6:00 AM
    static let sixAM = 24

    /// 8:00 AM
    static let eightAM = 32

    /// 9:00 AM
    static let nineAM = 36

    /// Noon
    static let noon = 48

    /// 3:00 PM
    static let threePM = 60

    /// 5:00 PM
    static let fivePM = 68

    /// 6:00 PM
    static let sixPM = 72

    /// 8:00 PM
    static let eightPM = 80

    /// 9:00 PM
    static let ninePM = 84

    /// 7:00 AM
    static let sevenAM = 28

    /// 7:30 PM
    static let sevenThirtyPM = 78

    /// End of day (midnight next day)
    static let endOfDay = 96

    // MARK: - Care Time Window

    static let defaultCareWindowStart = 28  // 7:00 AM
    static let defaultCareWindowEnd = 78    // 7:30 PM

    private static let careWindowStartKey = "careWindowStart"
    private static let careWindowEndKey = "careWindowEnd"

    /// Current care window start slot (reads from UserDefaults, falls back to default)
    static var careWindowStart: Int {
        let stored = UserDefaults.standard.integer(forKey: careWindowStartKey)
        return stored > 0 ? stored : defaultCareWindowStart
    }

    /// Current care window end slot (reads from UserDefaults, falls back to default)
    static var careWindowEnd: Int {
        let stored = UserDefaults.standard.integer(forKey: careWindowEndKey)
        return stored > 0 ? stored : defaultCareWindowEnd
    }

    /// Persist a custom care window
    static func setCareWindow(start: Int, end: Int) {
        UserDefaults.standard.set(start, forKey: careWindowStartKey)
        UserDefaults.standard.set(end, forKey: careWindowEndKey)
    }

    /// Reset care window to defaults
    static func resetCareWindow() {
        UserDefaults.standard.removeObject(forKey: careWindowStartKey)
        UserDefaults.standard.removeObject(forKey: careWindowEndKey)
    }

    /// Check if a slot range falls entirely within the care window
    static func isWithinCareWindow(start: Int, end: Int) -> Bool {
        start >= careWindowStart && end <= careWindowEnd
    }

    /// Clamp a slot range to the care window. Returns nil if the range is entirely outside.
    static func clampToCareWindow(start: Int, end: Int) -> (start: Int, end: Int)? {
        let clampedStart = max(start, careWindowStart)
        let clampedEnd = min(end, careWindowEnd)
        guard clampedStart < clampedEnd else { return nil }
        return (clampedStart, clampedEnd)
    }
}
