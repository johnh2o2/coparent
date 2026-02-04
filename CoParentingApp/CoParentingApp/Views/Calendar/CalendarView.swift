import SwiftUI
import KVKCalendar

/// Main calendar view with KVKCalendar integration
struct CalendarView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var showingViewPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Calendar
                KVKCalendarWrapper(
                    selectedDate: $viewModel.selectedDate,
                    calendarType: $viewModel.calendarType,
                    events: viewModel.displayBlocks,
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
                        ForEach([CalendarType.day, .week, .month], id: \.self) { type in
                            Button {
                                viewModel.calendarType = type
                            } label: {
                                Label(type.displayName, systemImage: type.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.calendarType.iconName)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isAIAssistantPresented = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isEditorPresented, onDismiss: {
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
            .sheet(isPresented: $viewModel.isAIAssistantPresented, onDismiss: {
                Task {
                    await viewModel.loadBlocks()
                }
            }) {
                AIAssistantSheet(calendarViewModel: viewModel)
            }
            .task {
                await viewModel.loadBlocks()
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
    }

    private var navigationTitle: String {
        let formatter = DateFormatter()

        switch viewModel.calendarType {
        case .day:
            formatter.dateFormat = "EEE, MMM d"
        case .week:
            formatter.dateFormat = "MMM d"
            let endDate = Calendar.current.date(byAdding: .day, value: 6, to: viewModel.selectedDate)!
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "d, yyyy"
            return "\(formatter.string(from: viewModel.selectedDate)) - \(endFormatter.string(from: endDate))"
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
