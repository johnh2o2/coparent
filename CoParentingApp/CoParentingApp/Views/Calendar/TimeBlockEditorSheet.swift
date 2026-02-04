import SwiftUI

/// Sheet for creating or editing a time block
struct TimeBlockEditorSheet: View {
    @Binding var block: TimeBlock
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // Date section
                Section("Date") {
                    DatePicker(
                        "Date",
                        selection: $block.date,
                        displayedComponents: .date
                    )
                }

                // Time section
                Section("Time") {
                    TimePicker(
                        label: "Start Time",
                        slot: $block.startSlot
                    )

                    TimePicker(
                        label: "End Time",
                        slot: $block.endSlot
                    )

                    // Duration display
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatDuration(block.durationMinutes))
                            .foregroundStyle(.secondary)
                    }
                }

                // Provider section
                Section("Care Provider") {
                    Picker("Provider", selection: $block.provider) {
                        ForEach(CareProvider.allCases.filter { $0 != .none }) { provider in
                            HStack {
                                Circle()
                                    .fill(provider.color)
                                    .frame(width: 12, height: 12)
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Notes section
                Section("Notes") {
                    TextField("Add notes...", text: Binding(
                        get: { block.notes ?? "" },
                        set: { block.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }

                // Delete button
                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Time Block", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(onDelete != nil ? "Edit Time Block" : "New Time Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(!isValid)
                }
            }
            .confirmationDialog(
                "Delete this time block?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var isValid: Bool {
        block.startSlot < block.endSlot && block.provider != .none
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "\(mins) minutes"
        }
    }
}

/// Custom time picker for 15-minute slots
struct TimePicker: View {
    let label: String
    @Binding var slot: Int

    private let slots = Array(0...96)

    var body: some View {
        Picker(label, selection: $slot) {
            ForEach(slots, id: \.self) { slotValue in
                Text(SlotUtility.formatSlot(slotValue))
                    .tag(slotValue)
            }
        }
    }
}

/// Color indicator for a provider
struct ProviderColorIndicator: View {
    let provider: CareProvider

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(provider.color)
                .frame(width: 20, height: 20)
            Text(provider.displayName)
        }
    }
}

/// Provider legend for the calendar
struct ProviderLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(CareProvider.allCases.filter { $0 != .none }) { provider in
                HStack(spacing: 4) {
                    Circle()
                        .fill(provider.color)
                        .frame(width: 10, height: 10)
                    Text(provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Preview

#Preview("Editor") {
    TimeBlockEditorSheet(
        block: .constant(TimeBlock(
            date: Date(),
            startSlot: 32,
            endSlot: 48,
            provider: .parentA,
            notes: "Morning routine"
        )),
        onSave: {},
        onCancel: {},
        onDelete: {}
    )
}

#Preview("New Block") {
    TimeBlockEditorSheet(
        block: .constant(TimeBlock(
            date: Date(),
            startSlot: 32,
            endSlot: 48,
            provider: .parentA
        )),
        onSave: {},
        onCancel: {},
        onDelete: nil
    )
}
