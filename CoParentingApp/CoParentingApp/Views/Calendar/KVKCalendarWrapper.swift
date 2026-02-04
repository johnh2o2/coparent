import SwiftUI
import UIKit
import EventKit
import KVKCalendar

/// UIViewControllerRepresentable wrapper for KVKCalendar
struct KVKCalendarWrapper: UIViewControllerRepresentable {
    @Binding var selectedDate: Date
    @Binding var calendarType: CalendarType
    var events: [TimeBlock]
    var onEventTapped: ((TimeBlock) -> Void)?
    var onDateSelected: ((Date) -> Void)?
    var onEventMoved: ((TimeBlock, Date, Int, Int) -> Void)?
    var onNewEventRequested: ((Date, Int, Int) -> Void)?

    func makeUIViewController(context: Context) -> KVKCalendarViewController {
        // Do NOT access calendarView here — it would trigger the lazy init
        // before the view hierarchy is set up. Delegate/dataSource are
        // assigned in updateUIViewController (called after viewDidLoad).
        return KVKCalendarViewController()
    }

    func updateUIViewController(_ uiViewController: KVKCalendarViewController, context: Context) {
        let kvkView = uiViewController.calendarView

        // Ensure delegate/dataSource are wired up (idempotent)
        if kvkView.delegate == nil {
            kvkView.delegate = context.coordinator
        }
        if kvkView.dataSource == nil {
            kvkView.dataSource = context.coordinator
        }
        context.coordinator.calendarView = kvkView

        // Keep the parent reference fresh so delegate callbacks write to
        // the current @Binding values
        context.coordinator.parent = self
        context.coordinator.events = events
        context.coordinator.onEventTapped = onEventTapped
        context.coordinator.onDateSelected = onDateSelected
        context.coordinator.onEventMoved = onEventMoved
        context.coordinator.onNewEventRequested = onNewEventRequested

        let typeChanged = context.coordinator.lastSetType != calendarType
        let dateChanged = !(context.coordinator.lastSetDate.map {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        } ?? false)

        if typeChanged || dateChanged {
            context.coordinator.lastSetType = calendarType
            context.coordinator.lastSetDate = selectedDate
            kvkView.set(type: calendarType, date: selectedDate)
        }

        // KVK needs a frame reload after type switches to lay out the new view hierarchy
        if typeChanged {
            kvkView.reloadFrame(uiViewController.view.bounds)
        }

        // Reload events
        kvkView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CalendarDelegate, CalendarDataSource {
        var parent: KVKCalendarWrapper
        var events: [TimeBlock] = []
        var calendarView: KVKCalendarView?
        var onEventTapped: ((TimeBlock) -> Void)?
        var onDateSelected: ((Date) -> Void)?
        var onEventMoved: ((TimeBlock, Date, Int, Int) -> Void)?
        var onNewEventRequested: ((Date, Int, Int) -> Void)?

        // Track last values sent to KVK to avoid redundant updates
        // and prevent feedback loops from delegate callbacks
        var lastSetType: CalendarType?
        var lastSetDate: Date?

        init(_ parent: KVKCalendarWrapper) {
            self.parent = parent
            self.events = parent.events
        }

        // MARK: - CalendarDataSource

        func eventsForCalendar(systemEvents: [EKEvent]) -> [Event] {
            events.map { timeBlock in
                let providerName = timeBlock.provider.displayName
                var event = Event(ID: timeBlock.id.uuidString)
                event.start = timeBlock.startTime
                event.end = timeBlock.endTime
                event.title = TextEvent(
                    timeline: providerName,
                    month: providerName,
                    list: providerName
                )
                event.color = Event.Color(timeBlock.provider.uiColor)
                event.isAllDay = false
                event.data = timeBlock.id.uuidString

                // Recurring blocks are expanded into concrete per-day instances by
                // CalendarViewModel before reaching here, so we always use .none.
                event.recurringType = .none

                return event
            }
        }

        // MARK: - CalendarDelegate

        func didSelectDates(_ dates: [Date], type: CalendarType, frame: CGRect?) {
            if let date = dates.first {
                parent.selectedDate = date
                onDateSelected?(date)
            }
        }

        func didSelectEvent(_ event: Event, type: CalendarType, frame: CGRect?) {
            if let idString = event.data as? String,
               let id = UUID(uuidString: idString),
               let timeBlock = events.first(where: { $0.id == id }) {
                onEventTapped?(timeBlock)
            }
        }

        func didChangeEvent(_ event: Event, start: Date?, end: Date?) {
            guard let start = start,
                  let end = end,
                  let idString = event.data as? String,
                  let id = UUID(uuidString: idString),
                  let timeBlock = events.first(where: { $0.id == id }) else {
                return
            }

            let newDate = Calendar.current.startOfDay(for: start)
            let startSlot = SlotUtility.slot(from: start)
            let endSlot = SlotUtility.slot(from: end)

            onEventMoved?(timeBlock, newDate, startSlot, endSlot)
        }

        func didAddNewEvent(_ event: Event, _ date: Date?) {
            guard let date = date else { return }

            let startSlot = SlotUtility.slot(from: event.start)
            let endSlot = SlotUtility.slot(from: event.end)

            onNewEventRequested?(date, startSlot, endSlot)
        }
    }
}

/// UIViewController that hosts the KVKCalendarView
///
/// IMPORTANT: `calendarView` is created with `.zero` frame intentionally.
/// Using `view.bounds` in a lazy var triggers `loadView()` → `viewDidLoad()`
/// re-entrantly, creating TWO KVKCalendarView instances. The real frame is
/// set in `viewDidLoad` after the view hierarchy exists.
class KVKCalendarViewController: UIViewController {
    private(set) lazy var calendarView: KVKCalendarView = {
        var style = Style()

        // General settings
        style.startWeekDay = .sunday
        style.defaultType = .week
        style.timeSystem = .twelve

        // Timeline settings (15-minute granularity)
        style.timeline.startHour = 6
        style.timeline.endHour = 22
        style.timeline.widthTime = 60
        style.timeline.heightTime = 60
        style.timeline.offsetTimeX = 8
        style.timeline.offsetTimeY = 0
        style.timeline.showLineHourMode = .today

        // Event settings
        style.event.iconFile = nil
        style.event.isEnableVisualSelect = true
        style.event.states = [.move, .resize]

        // Week settings
        style.week.colorBackground = .systemBackground
        style.week.colorDate = .label
        style.week.colorNameDay = .secondaryLabel
        style.week.colorCurrentDate = .systemBlue
        style.week.colorWeekendDate = .systemGray

        // Month settings
        style.month.isHiddenSeparator = false
        style.month.colorSeparator = .separator
        style.month.colorBackgroundWeekendDate = .secondarySystemBackground

        // Header settings
        style.headerScroll.colorBackground = .systemBackground
        style.headerScroll.isAnimateTitleDate = true

        // Use .zero frame to avoid triggering view.bounds (which causes
        // loadView → viewDidLoad re-entrancy). The real frame is set in
        // viewDidLoad after the subview is added.
        let calendar = KVKCalendarView(frame: .zero, date: Date(), style: style)
        calendar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return calendar
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(calendarView)
        calendarView.frame = view.bounds
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // KVKCalendar needs explicit frame updates to resize its internal views
        if calendarView.frame != view.bounds {
            calendarView.reloadFrame(view.bounds)
        }
    }

    func setCalendarType(_ type: CalendarType, date: Date) {
        calendarView.set(type: type, date: date)
    }
}

// MARK: - Calendar Type Extension

extension CalendarType {
    var displayName: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .list: return "List"
        }
    }

    var iconName: String {
        switch self {
        case .day: return "square"
        case .week: return "rectangle.split.3x1"
        case .month: return "calendar"
        case .year: return "calendar.badge.clock"
        case .list: return "list.bullet"
        }
    }
}
