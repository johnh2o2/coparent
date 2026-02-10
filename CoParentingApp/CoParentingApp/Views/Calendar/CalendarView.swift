import SwiftUI
import KVKCalendar

/// Main calendar view with KVKCalendar integration
struct CalendarView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var ownViewModel = CalendarViewModel()
    private var sharedViewModel: CalendarViewModel?

    private var viewModel: CalendarViewModel {
        sharedViewModel ?? ownViewModel
    }

    @State private var showingViewPicker = false

    init(sharedViewModel: CalendarViewModel? = nil) {
        self.sharedViewModel = sharedViewModel
    }

    /// Whether this view is embedded in a NavigationSplitView detail (iPad).
    /// When true, we skip the inner NavigationStack so the split view's
    /// sidebar toggle button remains visible and the detail resizes properly.
    private var isEmbeddedInSplitView: Bool {
        sharedViewModel != nil
    }

    var body: some View {
        if isEmbeddedInSplitView {
            calendarContent
        } else {
            NavigationStack {
                calendarContent
            }
        }
    }

    private var calendarContent: some View {
        ZStack {
            // Calendar
            KVKCalendarWrapper(
                    selectedDate: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.selectedDate = $0 }
                    ),
                    calendarType: Binding(
                        get: { viewModel.calendarType },
                        set: { viewModel.calendarType = $0 }
                    ),
                    events: viewModel.displayBlocks,
                    daysInWeek: horizontalSizeClass == .regular ? 7 : 3,
                    onEventTapped: { block in
                        viewModel.openBlockEditor(block)
                    },
                    onDateSelected: { date in
                        viewModel.selectedDate = date
                    },
                    onEventMoved: { block, newDate, startSlot, endSlot in
                        Task {
                            await viewModel.moveBlock(block, to: newDate, startSlot: startSlot, endSlot: endSlot)
                        }
                    },
                    onNewEventRequested: { date, startSlot, endSlot in
                        viewModel.openNewBlockEditor(date: date, startSlot: startSlot, endSlot: endSlot)
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                // Provider legend pinned to bottom
                ProviderLegend()
                    .frame(maxHeight: .infinity, alignment: .bottom)

                // Loading overlay (only show after a delay to avoid flash)
                if viewModel.isLoading && viewModel.displayBlocks.isEmpty {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }

            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.goToToday()
                    } label: {
                        Text("Today")
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack {
                        Button {
                            viewModel.goToPrevious()
                        } label: {
                            Image(systemName: "chevron.left")
                        }

                        Text(navigationTitle)
                            .font(.headline)
                            .frame(minWidth: 120)

                        Button {
                            viewModel.goToNext()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.calendarType = .day
                        } label: {
                            Label("Day", systemImage: CalendarType.day.iconName)
                        }
                        Button {
                            viewModel.calendarType = .week
                        } label: {
                            Label(horizontalSizeClass == .regular ? "Week" : "3-Day", systemImage: CalendarType.week.iconName)
                        }
                        Button {
                            viewModel.calendarType = .month
                        } label: {
                            Label("Month", systemImage: CalendarType.month.iconName)
                        }
                    } label: {
                        Image(systemName: viewModel.calendarType.iconName)
                    }
                }

                // Only show AI button on iPhone — on iPad it's in the sidebar
                if horizontalSizeClass != .regular {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.isAIAssistantPresented = true
                        } label: {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isEditorPresented },
                set: { viewModel.isEditorPresented = $0 }
            ), onDismiss: {
                Task {
                    await viewModel.loadBlocks()
                }
            }) {
                if let block = viewModel.editingBlock {
                    TimeBlockEditorSheet(
                        block: Binding(
                            get: { block },
                            set: { viewModel.editingBlock = $0 }
                        ),
                        onSave: {
                            Task {
                                await viewModel.saveEditingBlock()
                            }
                        },
                        onCancel: {
                            viewModel.cancelEditing()
                        },
                        onDelete: viewModel.timeBlocks.contains(where: { $0.id == block.id }) ? {
                            Task {
                                await viewModel.deleteBlock(block)
                                viewModel.cancelEditing()
                            }
                        } : nil
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isAIAssistantPresented },
                set: { viewModel.isAIAssistantPresented = $0 }
            ), onDismiss: {
                Task {
                    await viewModel.loadBlocks()
                }
            }) {
                AIAssistantSheet(calendarViewModel: viewModel)
            }
            .task {
                await viewModel.loadBlocks()
            }
            .onChange(of: viewModel.selectedDate) { _, newDate in
                // Reload when the date moves outside the loaded range
                // (e.g. swiping to a new month in KVK's month view)
                if viewModel.isOutsideLoadedRange(newDate) {
                    Task {
                        await viewModel.loadBlocks()
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }

    private var navigationTitle: String {
        let formatter = DateFormatter()

        switch viewModel.calendarType {
        case .day:
            formatter.dateFormat = "EEE, MMM d"
        case .week:
            formatter.dateFormat = "EEE, MMM d"
            let daysInView = horizontalSizeClass == .regular ? 6 : 2
            let endDate = Calendar.current.date(byAdding: .day, value: daysInView, to: viewModel.selectedDate)!
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "EEE, MMM d"
            return "\(formatter.string(from: viewModel.selectedDate)) – \(endFormatter.string(from: endDate))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
        default:
            formatter.dateFormat = "MMM yyyy"
        }

        return formatter.string(from: viewModel.selectedDate)
    }
}

// MARK: - Preview

#Preview {
    CalendarView()
}
