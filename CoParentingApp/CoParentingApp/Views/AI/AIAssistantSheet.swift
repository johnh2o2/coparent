import SwiftUI

/// Sheet for AI-powered schedule assistance with full lifecycle:
/// input -> processing -> review -> applying -> done
struct AIAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var voiceService = VoiceInputService()
    @State private var textInput = ""
    @State private var showingExamples = false
    @State private var sheetState: SheetState = .input
    @State private var pendingBatch: ScheduleChangeBatch?
    @State private var errorText: String?

    let calendarViewModel: CalendarViewModel

    enum SheetState {
        case input, processing, review, applying, done, error
    }

    var body: some View {
        NavigationStack {
            Group {
                switch sheetState {
                case .input:
                    inputView
                case .processing:
                    processingView
                case .review:
                    reviewView
                case .applying:
                    applyingView
                case .done:
                    doneView
                case .error:
                    errorView
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if sheetState == .input || sheetState == .error {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(sheetState != .input && sheetState != .error)
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)

                Text("Schedule Assistant")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Tell me what you'd like to change")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            // Voice input button
            VoiceInputButton(
                isRecording: voiceService.isRecording,
                transcribedText: voiceService.transcribedText,
                onToggle: {
                    Task {
                        if !voiceService.isAuthorized {
                            _ = await voiceService.requestAuthorization()
                            _ = await voiceService.requestMicrophoneAuthorization()
                        }
                        voiceService.toggleRecording()
                    }
                }
            )

            // Or divider
            HStack {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
            }
            .padding(.horizontal, 40)

            // Text input
            VStack(alignment: .leading, spacing: 8) {
                TextField("Type your request...", text: $textInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    showingExamples.toggle()
                } label: {
                    Label("Show examples", systemImage: "lightbulb")
                        .font(.caption)
                }
            }
            .padding(.horizontal)

            // Examples (collapsible)
            if showingExamples {
                ExamplesSection()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            // Submit button
            Button {
                submitCommand()
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("Submit")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSubmit ? .purple : .gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onChange(of: voiceService.transcribedText) { _, newValue in
            if !newValue.isEmpty && !voiceService.isRecording {
                textInput = newValue
            }
        }
        .animation(.easeInOut, value: showingExamples)
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)

            Text("Thinking...")
                .font(.title3)
                .fontWeight(.medium)

            Text("Analyzing your request and building schedule changes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Review View

    private var reviewView: some View {
        VStack(spacing: 0) {
            if let batch = pendingBatch {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .font(.title2)
                                    .foregroundStyle(.purple)

                                Text("Schedule Assistant")
                                    .font(.headline)
                            }

                            // Render AI summary as markdown
                            if let attributed = try? AttributedString(markdown: batch.summary, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                                Text(attributed)
                                    .font(.body)
                            } else {
                                Text(batch.summary)
                                    .font(.body)
                            }

                            Text(changeSummaryText(batch))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top)

                        // Day-by-day breakdown
                        let grouped = changesByDay(batch: batch)
                        let sortedDates = grouped.keys.sorted()

                        ForEach(sortedDates, id: \.self) { date in
                            if let changes = grouped[date] {
                                DayChangesSection(date: date, changes: changes)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }

                // Action buttons pinned at bottom
                VStack(spacing: 12) {
                    Divider()

                    HStack(spacing: 12) {
                        Button {
                            AIInteractionLog.shared.log(
                                command: batch.originalCommand,
                                summary: batch.summary,
                                changeCount: batch.changeCount,
                                wasApplied: false
                            )
                            calendarViewModel.rejectBatch(batch)
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            applyChanges(batch)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Apply All")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
    }

    // MARK: - Applying View

    private var applyingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)

            Text("Applying changes...")
                .font(.title3)
                .fontWeight(.medium)

            Text("Updating your schedule")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Done View

    private var doneView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("\(pendingBatch?.changeCount ?? 0) change\((pendingBatch?.changeCount ?? 0) == 1 ? "" : "s") applied")
                .font(.title3)
                .fontWeight(.medium)

            Text("Your schedule has been updated")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title3)
                .fontWeight(.medium)

            Text(errorText ?? "An unknown error occurred")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                sheetState = .input
                errorText = nil
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Try Again")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.purple)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !voiceService.transcribedText.isEmpty
    }

    private func submitCommand() {
        let command = textInput.isEmpty ? voiceService.transcribedText : textInput
        guard !command.isEmpty else { return }

        sheetState = .processing

        Task {
            let batch = await calendarViewModel.processAICommand(command)
            if let batch {
                pendingBatch = batch
                sheetState = .review
            } else {
                let error = calendarViewModel.errorMessage ?? "Failed to process your request"
                errorText = error
                sheetState = .error
                AIInteractionLog.shared.log(
                    command: command,
                    summary: "",
                    changeCount: 0,
                    wasApplied: false,
                    errorMessage: error
                )
            }
        }
    }

    private func applyChanges(_ batch: ScheduleChangeBatch) {
        sheetState = .applying

        Task {
            await calendarViewModel.applyBatch(batch)

            if let error = calendarViewModel.errorMessage {
                errorText = error
                sheetState = .error
                AIInteractionLog.shared.log(
                    command: batch.originalCommand,
                    summary: batch.summary,
                    changeCount: batch.changeCount,
                    wasApplied: false,
                    errorMessage: error
                )
            } else {
                AIInteractionLog.shared.log(
                    command: batch.originalCommand,
                    summary: batch.summary,
                    changeCount: batch.changeCount,
                    wasApplied: true
                )
                sheetState = .done
                // Auto-dismiss after 1.5 seconds
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            }
        }
    }

    private func changesByDay(batch: ScheduleChangeBatch) -> [Date: [ScheduleChange]] {
        Dictionary(grouping: batch.changes) { change in
            let date = change.proposedBlock?.date ?? change.originalBlock?.date ?? Date()
            return Calendar.current.startOfDay(for: date)
        }
    }

    private func uniqueDayCount(in batch: ScheduleChangeBatch) -> Int {
        changesByDay(batch: batch).keys.count
    }

    private func changeSummaryText(_ batch: ScheduleChangeBatch) -> String {
        let recurringCount = batch.changes.filter {
            ($0.proposedBlock?.recurrenceType ?? .none) != .none
        }.count
        let dayCount = uniqueDayCount(in: batch)
        if recurringCount > 0 {
            return "\(recurringCount) recurring block\(recurringCount == 1 ? "" : "s") across \(dayCount) day\(dayCount == 1 ? "" : "s")"
        }
        return "\(batch.changeCount) change\(batch.changeCount == 1 ? "" : "s") across \(dayCount) day\(dayCount == 1 ? "" : "s")"
    }
}

// MARK: - Day Changes Section

/// Groups changes for a single day with a header and list of individual changes
struct DayChangesSection: View {
    let date: Date
    let changes: [ScheduleChange]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header
            Text(dayHeaderString)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 6) {
                ForEach(changes) { change in
                    ChangeRow(change: change)
                }
            }
            .padding(.horizontal)
        }
    }

    private var dayHeaderString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

/// A single change row showing +/- indicator, provider color, and time range
struct ChangeRow: View {
    let change: ScheduleChange

    var body: some View {
        HStack(spacing: 10) {
            // Change type indicator
            Text(changeIndicator)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(indicatorColor)
                .frame(width: 20)

            // Provider color dot + name
            if let block = change.proposedBlock ?? change.originalBlock {
                Circle()
                    .fill(block.provider.color)
                    .frame(width: 10, height: 10)

                Text(block.provider.displayName)
                    .font(.subheadline)
                    .frame(width: 70, alignment: .leading)

                // Time range
                Text(SlotUtility.formatSlotRange(start: block.startSlot, end: block.endSlot))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Recurring indicator
                if block.recurrenceType != .none {
                    Image(systemName: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var changeIndicator: String {
        switch change.changeType {
        case .addBlock: return "+"
        case .removeBlock: return "\u{2212}"
        case .changeTime, .reassign, .swap: return "~"
        }
    }

    private var indicatorColor: Color {
        switch change.changeType {
        case .addBlock: return .green
        case .removeBlock: return .red
        case .changeTime, .reassign, .swap: return .orange
        }
    }
}

/// Voice input button with recording visualization
struct VoiceInputButton: View {
    let isRecording: Bool
    let transcribedText: String
    let onToggle: () -> Void

    @State private var animationAmount = 1.0

    var body: some View {
        VStack(spacing: 16) {
            Button {
                onToggle()
            } label: {
                ZStack {
                    // Pulsing background when recording
                    if isRecording {
                        Circle()
                            .fill(.purple.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .scaleEffect(animationAmount)
                            .opacity(2 - animationAmount)
                            .animation(
                                .easeInOut(duration: 1)
                                .repeatForever(autoreverses: false),
                                value: animationAmount
                            )
                    }

                    Circle()
                        .fill(isRecording ? .red : .purple)
                        .frame(width: 80, height: 80)

                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .onAppear {
                animationAmount = 2.0
            }

            // Transcribed text preview
            if isRecording || !transcribedText.isEmpty {
                Text(isRecording ? (transcribedText.isEmpty ? "Listening..." : transcribedText) : transcribedText)
                    .font(.callout)
                    .foregroundStyle(isRecording ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .frame(maxWidth: 280)
            } else {
                Text("Tap to speak")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Examples section showing sample commands
struct ExamplesSection: View {
    let examples = [
        "Move pickup to 8:15 AM",
        "Swap Tuesday and Thursday this week",
        "Add nanny from 12-6 on Friday",
        "Remove my morning block on Monday",
        "Set up weekly: M/W/F parent_a 7am-7:30pm, T/Th parent_b",
        "This Friday, have nanny cover 9am-3pm instead"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Example commands:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ForEach(examples, id: \.self) { example in
                HStack {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.purple)
                    Text(example)
                        .font(.callout)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AIAssistantSheet(calendarViewModel: CalendarViewModel.preview)
}
