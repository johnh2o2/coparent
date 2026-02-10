import Foundation
import SwiftAnthropic

/// Service for AI-powered schedule parsing and adjustments
@Observable
final class AIScheduleService {
    private var service: AnthropicService?
    private(set) var apiKey: String?

    var isProcessing = false
    var lastError: String?

    var isConfigured: Bool { service != nil }

    init(apiKey: String? = nil) {
        let key = apiKey
            ?? Self.savedAPIKey
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        configure(with: key)
    }

    /// Update the API key and reinitialize the service
    func configure(with apiKey: String?) {
        self.apiKey = apiKey
        if let key = apiKey, !key.isEmpty {
            self.service = AnthropicServiceFactory.service(apiKey: key, betaHeaders: nil)
        } else {
            self.service = nil
        }
    }

    // MARK: - Key Persistence

    private static let apiKeyKey = "anthropic_api_key"

    static var savedAPIKey: String? {
        UserDefaults.standard.string(forKey: apiKeyKey)
    }

    func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: Self.apiKeyKey)
        configure(with: key)
    }

    func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: Self.apiKeyKey)
        configure(with: nil)
    }

    // MARK: - Schedule Command Parsing

    /// Parse a natural language schedule command, returning a batch of changes.
    func parseScheduleCommand(_ command: String, currentBlocks: [TimeBlock], currentUser: User? = nil) async throws -> ScheduleChangeBatch {
        // If not yet configured, check if a key was saved by another instance (e.g. Settings)
        if service == nil, let savedKey = Self.savedAPIKey {
            configure(with: savedKey)
        }

        guard let service = service else {
            throw AIServiceError.notConfigured
        }

        isProcessing = true
        defer { isProcessing = false }

        let systemPrompt = buildSystemPrompt(blocks: currentBlocks, currentUser: currentUser)
        let tools = buildTools()

        do {
            let message = MessageParameter.Message(
                role: .user,
                content: .text(command)
            )

            let parameter = MessageParameter(
                model: .other("claude-sonnet-4-5-20250929"),
                messages: [message],
                maxTokens: 4096,
                system: .text(systemPrompt),
                tools: tools
            )

            let response = try await service.createMessage(parameter)

            // Track API usage
            APIUsageTracker.shared.record(
                inputTokens: response.usage.inputTokens ?? 0,
                outputTokens: response.usage.outputTokens,
                cacheCreationTokens: response.usage.cacheCreationInputTokens ?? 0,
                cacheReadTokens: response.usage.cacheReadInputTokens ?? 0
            )

            return try parseResponse(response, originalCommand: command, currentBlocks: currentBlocks)

        } catch let error as AIServiceError {
            lastError = error.localizedDescription
            throw error
        } catch let error as APIError {
            let message = error.displayDescription
            lastError = message
            throw AIServiceError.apiError(message)
        } catch {
            lastError = error.localizedDescription
            throw AIServiceError.apiError(error.localizedDescription)
        }
    }

    // MARK: - Activity Metadata Generation

    /// Metadata extracted from a single AI call for activity journal entries.
    struct ActivityMetadata: Codable {
        let title: String           // Short label, e.g. "Set default schedule"
        let purpose: String?        // Why the change was made
        let datesImpacted: String   // e.g. "Mon–Fri recurring, starting Feb 10"
        let careTimeDelta: String?  // e.g. "+12.5h John, +10h Sarah weekly"
        let notificationMessage: String // Warm coparent notification
    }

    /// Generate all activity metadata in a single AI call.
    /// Accepts a structured change breakdown for better context.
    func generateActivityMetadata(
        narration: String,
        summary: String,
        changeCount: Int,
        userName: String,
        userRole: String? = nil,
        changeBreakdown: String? = nil
    ) async -> ActivityMetadata {
        // Build a meaningful fallback title from the user's narration
        let fallbackTitle: String
        let trimmedNarration = narration.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNarration.isEmpty {
            fallbackTitle = "\(userName) updated the schedule"
        } else {
            // Capitalize first letter and truncate to keep it concise
            let capitalized = trimmedNarration.prefix(1).uppercased() + trimmedNarration.dropFirst()
            if capitalized.count <= 60 {
                fallbackTitle = capitalized
            } else {
                fallbackTitle = String(capitalized.prefix(57)) + "..."
            }
        }

        let fallback = ActivityMetadata(
            title: fallbackTitle,
            purpose: nil,
            datesImpacted: "Today",
            careTimeDelta: nil,
            notificationMessage: "\(userName) made \(changeCount) schedule change\(changeCount == 1 ? "" : "s")."
        )

        guard let service = service else { return fallback }

        // Build provider name mapping for the prompt
        let providerMapping = [
            "parent_a": CareProvider.parentA.displayName,
            "parent_b": CareProvider.parentB.displayName,
            "nanny": CareProvider.nanny.displayName
        ]
        let providerContext = providerMapping.map { "\($0.key) = \($0.value)" }.joined(separator: ", ")

        let roleContext: String
        if let role = userRole {
            roleContext = "\nThe user \(userName) is \(role). Express care time impact from their perspective (e.g. \"+24h to your year\", \"-8h from your year\")."
        } else {
            roleContext = ""
        }

        let systemPrompt = """
        You extract structured metadata about a schedule change. Respond with ONLY valid JSON, no markdown fences, no commentary.

        Provider name mapping: \(providerContext)
        Always use the display names above — never say "Parent A" or "Parent B" or use internal IDs like "parent_a".
        Do not use markdown formatting anywhere in the values — plain text only.
        \(roleContext)

        Return this exact JSON shape:
        {
          "title": "A specific, human-readable summary of what changed. Incorporate the user's own words and intent. Good examples: 'John takes Saturday mornings', 'New weekly schedule: M/W/F John, T/Th Sarah', 'Nanny covers Friday afternoon', 'Swapped Tuesday and Thursday', 'Extended morning pickup to 8:15'. Bad examples (too generic): 'Updated the schedule', 'Made schedule changes', 'John made 19 changes'. The title should tell someone at a glance WHAT changed without needing to open the detail view.",
          "purpose": "one sentence explaining why this change was made based on what the user said, or null if unclear",
          "datesImpacted": "concise description of affected dates, e.g. Mon–Fri recurring starting Feb 10",
          "careTimeDelta": "estimated net impact on yearly care time in hours, e.g. '+24h to your year' or '-8h from your year' or 'No net change'. Think about hours per week times weeks affected. Use null only if truly impossible to estimate.",
          "notificationMessage": "A specific, warm 1-2 sentence note for the other coparent describing what changed. Include concrete details like days, times, or patterns. Good: 'John set up a new weekly routine — he has Mon/Wed/Fri mornings and you have Tue/Thu. Nanny covers afternoons.' Bad: 'John made 19 schedule changes.'"
        }
        """

        var userMessage = """
        The user "\(userName)" said: "\(narration)"

        AI summary of the changes: \(summary)
        Total changes: \(changeCount)
        """

        if let breakdown = changeBreakdown {
            userMessage += "\n\nDetailed breakdown of each change:\n\(breakdown)"
        }

        do {
            let message = MessageParameter.Message(role: .user, content: .text(userMessage))
            let parameter = MessageParameter(
                model: .other("claude-sonnet-4-5-20250929"),
                messages: [message],
                maxTokens: 512,
                system: .text(systemPrompt)
            )

            let response = try await service.createMessage(parameter)

            APIUsageTracker.shared.record(
                inputTokens: response.usage.inputTokens ?? 0,
                outputTokens: response.usage.outputTokens,
                cacheCreationTokens: response.usage.cacheCreationInputTokens ?? 0,
                cacheReadTokens: response.usage.cacheReadInputTokens ?? 0
            )

            for content in response.content {
                if case .text(let text) = content {
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = cleaned.data(using: .utf8),
                       let metadata = try? JSONDecoder().decode(ActivityMetadata.self, from: data) {
                        return metadata
                    }
                }
            }
        } catch {
            print("[AIScheduleService] Metadata generation failed: \(error.localizedDescription)")
        }

        return fallback
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(blocks: [TimeBlock], currentUser: User? = nil) -> String {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .full

        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")

        var prompt = """
        You are an AI assistant helping co-parents manage their childcare schedule.
        Today is \(formatter.string(from: today)) (\(isoFormatter.string(from: today))).

        The schedule uses 15-minute time slots (0-95 per day):
        - Slot 0 = 00:00 (midnight)
        - Slot 24 = 06:00 AM
        - Slot 28 = 07:00 AM
        - Slot 30 = 07:30 AM — use this for "7:30 AM" or "7:30pm" style times
        - Slot 32 = 08:00 AM
        - Slot 48 = 12:00 PM (noon)
        - Slot 72 = 06:00 PM
        - Slot 78 = 07:30 PM — use this for "7:30 PM"
        - Slot 96 = midnight (end of day)
        Formula: slot = hour * 4 + (minute / 15)

        CARE TIME WINDOW: All blocks MUST have start_slot >= \(SlotUtility.careWindowStart) and end_slot <= \(SlotUtility.careWindowEnd).
        Never create blocks outside this window (\(SlotUtility.formatSlot(SlotUtility.careWindowStart)) - \(SlotUtility.formatSlot(SlotUtility.careWindowEnd))). Time outside the window is sleep/personal time and must not be scheduled.

        Providers (internal ID → display name):
        - parent_a → \(CareProvider.parentA.displayName)
        - parent_b → \(CareProvider.parentB.displayName)
        - nanny → \(CareProvider.nanny.displayName)
        Always use the display names above in your responses. Never show "Parent A", "Parent B", or internal IDs to the user.
        \(Self.userIdentityPrompt(currentUser))
        Current schedule:
        """

        // Separate recurring and non-recurring blocks for display
        let recurringBlocks = blocks.filter { $0.recurrenceType != .none }
        let nonRecurringBlocks = blocks.filter { $0.recurrenceType == .none }

        // Show recurring templates first (grouped by day-of-week)
        if !recurringBlocks.isEmpty {
            let calendar = Calendar.current
            prompt += "\n\nRECURRING BLOCKS (repeat every week automatically):"
            let byWeekday = Dictionary(grouping: recurringBlocks) { block in
                calendar.component(.weekday, from: block.date)
            }
            let weekdayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            for weekday in byWeekday.keys.sorted() {
                prompt += "\n  \(weekdayNames[weekday]):"
                for block in byWeekday[weekday]!.sorted(by: { $0.startSlot < $1.startSlot }) {
                    let startTime = SlotUtility.formatSlot(block.startSlot)
                    let endTime = SlotUtility.formatSlot(block.endSlot)
                    prompt += "\n    - \(block.provider.displayName) (\(block.provider.rawValue)): \(startTime) - \(endTime) (slots \(block.startSlot)-\(block.endSlot)) [RECURRING WEEKLY]"
                }
            }
        }

        // Show non-recurring blocks by date
        let groupedBlocks = Dictionary(grouping: nonRecurringBlocks) { block in
            Calendar.current.startOfDay(for: block.date)
        }

        if !groupedBlocks.isEmpty {
            prompt += "\n\nSINGLE-DAY BLOCKS:"
            for date in groupedBlocks.keys.sorted() {
                formatter.dateFormat = "EEEE, MMM d"
                prompt += "\n\n\(formatter.string(from: date)) (\(isoFormatter.string(from: date))):"

                for block in groupedBlocks[date]!.sorted(by: { $0.startSlot < $1.startSlot }) {
                    let startTime = SlotUtility.formatSlot(block.startSlot)
                    let endTime = SlotUtility.formatSlot(block.endSlot)
                    prompt += "\n  - \(block.provider.displayName) (\(block.provider.rawValue)): \(startTime) - \(endTime) (slots \(block.startSlot)-\(block.endSlot))"
                    if let notes = block.notes {
                        prompt += " (\(notes))"
                    }
                }
            }
        }

        if recurringBlocks.isEmpty && groupedBlocks.isEmpty {
            prompt += "\n(No blocks currently scheduled.)"
        }

        prompt += """

        \nYour job is to understand the user's request and use the appropriate tools to make schedule changes.
        Always explain what you're doing in a friendly, helpful way.
        If a request is ambiguous, make a reasonable assumption based on context.
        Times like "8:15" should be converted to the nearest 15-minute slot.

        WEEKLY / RECURRING SCHEDULES:
        When the user asks for a weekly recurring schedule, use the `set_weekly_schedule` tool.
        This is a SINGLE tool call that takes the entire week pattern and creates recurring blocks automatically.
        It replaces ALL existing blocks. Do NOT use set_day_schedule or clear_day for recurring schedules.
        Do NOT create individual blocks for each week — that will exceed token limits.

        MULTI-DAY NON-RECURRING SCHEDULES:
        When the user asks to set up a schedule for specific dates (not recurring):
        1. Call `clear_day` then `set_day_schedule` for each day.

        SINGLE-DAY OVERRIDES (e.g. "I'm taking her all day Tuesday"):
        Use `set_day_schedule` with the replacement blocks for that date (NOT recurring).
        Do NOT use `clear_day` with clear_recurring=true — the recurring schedule must survive.
        The app automatically suppresses recurring blocks when a non-recurring override exists for the same time slot on that day. The recurring schedule resumes on all other days.

        For simple single-block changes, use: change_time, add_block, remove_block, or swap_days.

        PAST DATES: Users may ask to set or modify events on dates that have already passed (retroactive scheduling). This is fully supported. Use any date the user requests — past, present, or future. For set_weekly_schedule, use start_date to begin the schedule before today if needed.

        IMPORTANT: In all your text responses, use people's actual display names (as listed in the provider mapping above). Never say "Parent A" or "Parent B" — always use their configured names.
        """

        return prompt
    }

    // MARK: - Tools

    private func buildTools() -> [MessageParameter.Tool] {
        [
            MessageParameter.Tool(
                name: "change_time",
                description: "Change the start or end time of an existing schedule block",
                inputSchema: .init(
                    type: .object,
                    properties: [
                        "date": .init(type: .string, description: "Date in YYYY-MM-DD format"),
                        "provider": .init(type: .string, description: "Provider: parent_a, parent_b, or nanny"),
                        "new_start_slot": .init(type: .integer, description: "New start time slot (0-95)"),
                        "new_end_slot": .init(type: .integer, description: "New end time slot (0-96)"),
                        "explanation": .init(type: .string, description: "Brief explanation of the change")
                    ],
                    required: ["date", "provider", "new_start_slot", "new_end_slot", "explanation"]
                )
            ),
            MessageParameter.Tool(
                name: "swap_days",
                description: "Swap schedules between two days",
                inputSchema: .init(
                    type: .object,
                    properties: [
                        "date1": .init(type: .string, description: "First date in YYYY-MM-DD format"),
                        "date2": .init(type: .string, description: "Second date in YYYY-MM-DD format"),
                        "explanation": .init(type: .string, description: "Brief explanation of the swap")
                    ],
                    required: ["date1", "date2", "explanation"]
                )
            ),
            MessageParameter.Tool(
                name: "add_block",
                description: "Add a new schedule block for a single time range on a single day. Supports optional recurrence.",
                inputSchema: .init(
                    type: .object,
                    properties: [
                        "date": .init(type: .string, description: "Date in YYYY-MM-DD format"),
                        "provider": .init(type: .string, description: "Provider: parent_a, parent_b, or nanny"),
                        "start_slot": .init(type: .integer, description: "Start time slot (0-95)"),
                        "end_slot": .init(type: .integer, description: "End time slot (0-96)"),
                        "notes": .init(type: .string, description: "Optional notes for the block"),
                        "recurring": .init(type: .string, description: "Optional recurrence: weekly, daily, monthly, yearly"),
                        "recurring_end_date": .init(type: .string, description: "Optional end date for recurrence in YYYY-MM-DD format"),
                        "explanation": .init(type: .string, description: "Brief explanation")
                    ],
                    required: ["date", "provider", "start_slot", "end_slot", "explanation"]
                )
            ),
            MessageParameter.Tool(
                name: "remove_block",
                description: "Remove a schedule block",
                inputSchema: .init(
                    type: .object,
                    properties: [
                        "date": .init(type: .string, description: "Date in YYYY-MM-DD format"),
                        "provider": .init(type: .string, description: "Provider: parent_a, parent_b, or nanny"),
                        "start_slot": .init(type: .integer, description: "Start time slot of block to remove"),
                        "explanation": .init(type: .string, description: "Brief explanation")
                    ],
                    required: ["date", "provider", "start_slot", "explanation"]
                )
            ),
            MessageParameter.Tool(
                name: "set_day_schedule",
                description: "Set or replace all schedule blocks for a single day. Use after clear_day to rebuild a day's schedule. Each entry in the blocks array becomes one time block. Supports optional recurrence so blocks repeat automatically.",
                inputSchema: .init(
                    type: .object,
                    properties: [
                        "date": .init(type: .string, description: "Date in YYYY-MM-DD format"),
                        "blocks": .init(
                            type: .array,
                            description: "Array of block objects to create for this day",
                            items: .init(
                                type: .object,
                                properties: [
                                    "provider": .init(type: .string, description: "Provider: parent_a, parent_b, or nanny"),
                                    "start_slot": .init(type: .integer, description: "Start time slot (0-95)"),
                                    "end_slot": .init(type: .integer, description: "End time slot (0-96)"),
                                    "notes": .init(type: .string, description: "Optional notes")
                                ]
                            )
                        ),
                        "recurring": .init(type: .string, description: "Optional recurrence: weekly, daily, monthly, yearly. All blocks in this call will recur."),
                        "recurring_end_date": .init(type: .string, description: "Optional end date for recurrence in YYYY-MM-DD format"),
                        "explanation": .init(type: .string, description: "Brief explanation of the schedule for this day")
                    ],
                    required: ["date", "blocks", "explanation"]
                )
            ),
            MessageParameter.Tool(
                name: "clear_day",
                description: "Remove non-recurring schedule blocks for a specific day. Optionally filter by provider. WARNING: Only set clear_recurring=true when permanently changing the weekly pattern — never for single-day overrides, as it deletes the recurring template for ALL future weeks.",
                inputSchema: .init(
                    type: .object,
                    properties: [
                        "date": .init(type: .string, description: "Date in YYYY-MM-DD format"),
                        "provider": .init(type: .string, description: "Optional: parent_a, parent_b, or nanny. If omitted, clears all providers."),
                        "clear_recurring": .init(type: .boolean, description: "Optional: if true, also removes recurring blocks whose day-of-week matches this date"),
                        "explanation": .init(type: .string, description: "Brief explanation")
                    ],
                    required: ["date", "explanation"]
                )
            ),
            MessageParameter.Tool(
                name: "set_weekly_schedule",
                description: "Set up a complete weekly recurring schedule with a SINGLE call. This REPLACES ALL existing blocks (recurring and non-recurring). Provide ALL blocks for the entire week. Each block must specify its day_of_week. The schedule will automatically repeat every week for the given number of weeks. Use this whenever the user asks for a recurring or weekly schedule.",
                inputSchema: .init(
                    type: .object,
                    properties: [
                        "blocks": .init(
                            type: .array,
                            description: "Array of ALL blocks for the entire week. Each block specifies its day_of_week.",
                            items: .init(
                                type: .object,
                                properties: [
                                    "day_of_week": .init(type: .string, description: "Day: monday, tuesday, wednesday, thursday, friday, saturday, or sunday"),
                                    "provider": .init(type: .string, description: "Provider: parent_a, parent_b, or nanny"),
                                    "start_slot": .init(type: .integer, description: "Start time slot (0-95). Formula: hour*4 + minute/15"),
                                    "end_slot": .init(type: .integer, description: "End time slot (0-96)"),
                                    "notes": .init(type: .string, description: "Optional notes")
                                ]
                            )
                        ),
                        "start_date": .init(type: .string, description: "Optional start date in YYYY-MM-DD format. The schedule begins on this date. Defaults to today if omitted. Use a past date for retroactive scheduling."),
                        "duration_weeks": .init(type: .integer, description: "How many weeks this schedule repeats. Use 52 for one year."),
                        "explanation": .init(type: .string, description: "Brief explanation of the schedule")
                    ],
                    required: ["blocks", "duration_weeks", "explanation"]
                )
            )
        ]
    }

    // MARK: - Response Parsing

    /// Parse a response that may contain multiple tool_use blocks into a batch.
    func parseResponse(_ response: MessageResponse, originalCommand: String, currentBlocks: [TimeBlock]) throws -> ScheduleChangeBatch {
        var changes: [ScheduleChange] = []
        var textSummary = ""

        for content in response.content {
            switch content {
            case .text(let text):
                if !text.isEmpty {
                    textSummary += (textSummary.isEmpty ? "" : " ") + text
                }
            case .toolUse(let toolUse):
                let parsed = try parseToolUse(toolUse, currentBlocks: currentBlocks)
                // Filter out add/change actions that would create 0-duration blocks
                let valid = parsed.filter { change in
                    if let proposed = change.proposedBlock, !proposed.isValid {
                        print("[AIService] Discarding 0-duration block: \(proposed.provider.rawValue) slot \(proposed.startSlot)-\(proposed.endSlot)")
                        return false
                    }
                    return true
                }
                changes.append(contentsOf: valid)
            }
        }

        guard !changes.isEmpty else {
            throw AIServiceError.noActionFound
        }

        let summary = textSummary.isEmpty
            ? "\(changes.count) schedule change\(changes.count == 1 ? "" : "s")"
            : textSummary

        return ScheduleChangeBatch(
            changes: changes,
            summary: summary,
            originalCommand: originalCommand
        )
    }

    /// Parse a single tool_use block into one or more ScheduleChange items.
    /// `set_day_schedule` produces one ScheduleChange per block entry;
    /// `clear_day` produces one ScheduleChange per matching existing block.
    func parseToolUse(_ toolUse: MessageResponse.Content.ToolUse, currentBlocks: [TimeBlock]) throws -> [ScheduleChange] {
        let input = toolUse.input
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        // Debug logging for tool input parsing
        print("[AIService] Parsing tool: \(toolUse.name), input keys: \(Array(input.keys))")
        for (key, value) in input {
            print("[AIService]   \(key) = \(value)")
        }

        switch toolUse.name {
        case "change_time":
            guard let dateString = input["date"]?.stringValue,
                  let date = dateFormatter.date(from: dateString),
                  let providerString = input["provider"]?.stringValue,
                  let provider = CareProvider(rawValue: providerString),
                  let newStartSlot = input["new_start_slot"]?.intValue,
                  let newEndSlot = input["new_end_slot"]?.intValue,
                  let explanation = input["explanation"]?.stringValue else {
                throw AIServiceError.invalidToolInput(tool: "change_time", keys: Array(input.keys))
            }

            let originalBlock = currentBlocks.first {
                Calendar.current.isDate($0.date, inSameDayAs: date) && $0.provider == provider
            }

            let proposedBlock = TimeBlock(
                id: originalBlock?.id ?? UUID(),
                date: date,
                startSlot: newStartSlot,
                endSlot: newEndSlot,
                provider: provider,
                notes: originalBlock?.notes
            )

            return [ScheduleChange(
                changeType: .changeTime,
                originalBlock: originalBlock,
                proposedBlock: proposedBlock,
                suggestedByAI: true,
                aiExplanation: explanation
            )]

        case "swap_days":
            guard let date1String = input["date1"]?.stringValue,
                  let date1 = dateFormatter.date(from: date1String),
                  let date2String = input["date2"]?.stringValue,
                  let date2 = dateFormatter.date(from: date2String),
                  let explanation = input["explanation"]?.stringValue else {
                throw AIServiceError.invalidToolInput(tool: "swap_days", keys: Array(input.keys))
            }

            let blocksDay1 = currentBlocks.filter { Calendar.current.isDate($0.date, inSameDayAs: date1) }
            let blocksDay2 = currentBlocks.filter { Calendar.current.isDate($0.date, inSameDayAs: date2) }

            guard let firstBlock = blocksDay1.first, let secondBlock = blocksDay2.first else {
                throw AIServiceError.blockNotFound
            }

            return [ScheduleChange(
                changeType: .swap,
                originalBlock: firstBlock,
                proposedBlock: TimeBlock(
                    date: date1,
                    startSlot: firstBlock.startSlot,
                    endSlot: firstBlock.endSlot,
                    provider: secondBlock.provider
                ),
                secondaryOriginalBlock: secondBlock,
                secondaryProposedBlock: TimeBlock(
                    date: date2,
                    startSlot: secondBlock.startSlot,
                    endSlot: secondBlock.endSlot,
                    provider: firstBlock.provider
                ),
                suggestedByAI: true,
                aiExplanation: explanation
            )]

        case "add_block":
            guard let dateString = input["date"]?.stringValue,
                  let date = dateFormatter.date(from: dateString),
                  let providerString = input["provider"]?.stringValue,
                  let provider = CareProvider(rawValue: providerString),
                  let startSlot = input["start_slot"]?.intValue,
                  let endSlot = input["end_slot"]?.intValue,
                  let explanation = input["explanation"]?.stringValue else {
                throw AIServiceError.invalidToolInput(tool: "add_block", keys: Array(input.keys))
            }

            let notes = input["notes"]?.stringValue
            let recurrence = Self.parseRecurrenceType(input["recurring"]?.stringValue)
            let recurrenceEnd = Self.parseRecurrenceEndDate(input["recurring_end_date"]?.stringValue, formatter: dateFormatter)

            return [ScheduleChange(
                changeType: .addBlock,
                proposedBlock: TimeBlock(
                    date: date,
                    startSlot: startSlot,
                    endSlot: endSlot,
                    provider: provider,
                    notes: notes,
                    recurrenceType: recurrence,
                    recurrenceEndDate: recurrenceEnd
                ),
                suggestedByAI: true,
                aiExplanation: explanation
            )]

        case "remove_block":
            guard let dateString = input["date"]?.stringValue,
                  let date = dateFormatter.date(from: dateString),
                  let providerString = input["provider"]?.stringValue,
                  let provider = CareProvider(rawValue: providerString),
                  let startSlot = input["start_slot"]?.intValue,
                  let explanation = input["explanation"]?.stringValue else {
                throw AIServiceError.invalidToolInput(tool: "remove_block", keys: Array(input.keys))
            }

            let originalBlock = currentBlocks.first {
                Calendar.current.isDate($0.date, inSameDayAs: date) &&
                $0.provider == provider &&
                $0.startSlot == startSlot
            }

            return [ScheduleChange(
                changeType: .removeBlock,
                originalBlock: originalBlock,
                suggestedByAI: true,
                aiExplanation: explanation
            )]

        case "set_day_schedule":
            guard let dateString = input["date"]?.stringValue,
                  let date = dateFormatter.date(from: dateString),
                  let blocksContent = input["blocks"]?.arrayValue,
                  let explanation = input["explanation"]?.stringValue else {
                throw AIServiceError.invalidToolInput(tool: "set_day_schedule", keys: Array(input.keys))
            }

            let recurrence = Self.parseRecurrenceType(input["recurring"]?.stringValue)
            let recurrenceEnd = Self.parseRecurrenceEndDate(input["recurring_end_date"]?.stringValue, formatter: dateFormatter)

            var changes: [ScheduleChange] = []

            for blockContent in blocksContent {
                guard let dict = blockContent.dictionaryValue,
                      let providerString = dict["provider"]?.stringValue,
                      let provider = CareProvider(rawValue: providerString),
                      let startSlot = dict["start_slot"]?.intValue,
                      let endSlot = dict["end_slot"]?.intValue else {
                    continue
                }

                let notes = dict["notes"]?.stringValue

                changes.append(ScheduleChange(
                    changeType: .addBlock,
                    proposedBlock: TimeBlock(
                        date: date,
                        startSlot: startSlot,
                        endSlot: endSlot,
                        provider: provider,
                        notes: notes,
                        recurrenceType: recurrence,
                        recurrenceEndDate: recurrenceEnd
                    ),
                    suggestedByAI: true,
                    aiExplanation: explanation
                ))
            }

            return changes

        case "clear_day":
            guard let dateString = input["date"]?.stringValue,
                  let date = dateFormatter.date(from: dateString),
                  let explanation = input["explanation"]?.stringValue else {
                throw AIServiceError.invalidToolInput(tool: "clear_day", keys: Array(input.keys))
            }

            let providerFilter: CareProvider?
            if let providerString = input["provider"]?.stringValue {
                providerFilter = CareProvider(rawValue: providerString)
            } else {
                providerFilter = nil
            }

            let clearRecurring = input["clear_recurring"]?.boolValue ?? false
            let calendar = Calendar.current
            let targetWeekday = calendar.component(.weekday, from: date)

            let matchingBlocks = currentBlocks.filter { block in
                // Exact date match
                let exactMatch = calendar.isDate(block.date, inSameDayAs: date)
                // Recurring day-of-week match
                let recurringMatch = clearRecurring &&
                    block.recurrenceType != .none &&
                    calendar.component(.weekday, from: block.date) == targetWeekday
                guard exactMatch || recurringMatch else { return false }
                if let provider = providerFilter {
                    return block.provider == provider
                }
                return true
            }

            return matchingBlocks.map { block in
                ScheduleChange(
                    changeType: .removeBlock,
                    originalBlock: block,
                    suggestedByAI: true,
                    aiExplanation: explanation
                )
            }

        case "set_weekly_schedule":
            guard let blocksContent = input["blocks"]?.arrayValue,
                  let durationWeeks = input["duration_weeks"]?.intValue,
                  let explanation = input["explanation"]?.stringValue else {
                throw AIServiceError.invalidToolInput(tool: "set_weekly_schedule", keys: Array(input.keys))
            }

            let calendar = Calendar.current

            // Support optional start_date for retroactive scheduling
            let referenceDate: Date
            if let startDateStr = input["start_date"]?.stringValue,
               let parsed = dateFormatter.date(from: startDateStr) {
                referenceDate = parsed
            } else {
                referenceDate = Date()
            }
            let endDate = calendar.date(byAdding: .weekOfYear, value: durationWeeks, to: referenceDate)!

            // Map day names to weekday numbers (Sunday=1 ... Saturday=7)
            let dayMap: [String: Int] = [
                "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                "thursday": 5, "friday": 6, "saturday": 7
            ]

            // First: remove ALL existing blocks (recurring and non-recurring)
            var changes: [ScheduleChange] = currentBlocks.map { block in
                ScheduleChange(
                    changeType: .removeBlock,
                    originalBlock: block,
                    suggestedByAI: true,
                    aiExplanation: "Clearing existing schedule to replace with new weekly schedule"
                )
            }

            // Then: create recurring weekly blocks for each entry
            for blockContent in blocksContent {
                guard let dict = blockContent.dictionaryValue,
                      let dayString = dict["day_of_week"]?.stringValue?.lowercased(),
                      let targetWeekday = dayMap[dayString],
                      let providerString = dict["provider"]?.stringValue,
                      let provider = CareProvider(rawValue: providerString),
                      let startSlot = dict["start_slot"]?.intValue,
                      let endSlot = dict["end_slot"]?.intValue else {
                    continue
                }

                let notes = dict["notes"]?.stringValue

                // Find the first occurrence of this weekday from the reference date
                let refWeekday = calendar.component(.weekday, from: referenceDate)
                var daysUntil = targetWeekday - refWeekday
                if daysUntil < 0 { daysUntil += 7 }
                let baseDate = calendar.date(byAdding: .day, value: daysUntil, to: referenceDate)!

                changes.append(ScheduleChange(
                    changeType: .addBlock,
                    proposedBlock: TimeBlock(
                        date: baseDate,
                        startSlot: startSlot,
                        endSlot: endSlot,
                        provider: provider,
                        notes: notes,
                        recurrenceType: .everyWeek,
                        recurrenceEndDate: endDate
                    ),
                    suggestedByAI: true,
                    aiExplanation: explanation
                ))
            }

            return changes

        default:
            throw AIServiceError.unknownTool(toolUse.name)
        }
    }

    // MARK: - User Identity

    private static func userIdentityPrompt(_ user: User?) -> String {
        guard let user = user else { return "" }
        let firstName = user.displayName.components(separatedBy: " ").first ?? user.displayName
        return """

        The user speaking to you is \(user.displayName) (provider ID: \(user.asCareProvider.rawValue)).
        When the user says "I" or "my", they mean \(firstName).
        Address them by their first name (\(firstName)) in your responses.
        In responses, always use the display names listed above. Never use internal identifiers like "parent_a" or generic labels like "Parent A". Do not use markdown formatting.
        """
    }

    // MARK: - Recurrence Helpers

    private static func parseRecurrenceType(_ value: String?) -> RecurrenceType {
        guard let value = value?.lowercased() else { return .none }
        switch value {
        case "daily":   return .everyDay
        case "weekly":  return .everyWeek
        case "monthly": return .everyMonth
        case "yearly":  return .everyYear
        default:        return .none
        }
    }

    private static func parseRecurrenceEndDate(_ value: String?, formatter: DateFormatter) -> Date? {
        guard let value = value else { return nil }
        return formatter.date(from: value)
    }
}

// MARK: - DynamicContent Helpers

extension MessageResponse.Content.DynamicContent {
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        // API sometimes returns numbers where strings are expected
        case .integer(let value): return String(value)
        case .double(let value): return String(value)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .integer(let value): return value
        // API often returns integers as doubles (JSON has no int/float distinction)
        case .double(let value): return Int(value)
        // API sometimes returns numbers as strings
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .integer(let value): return Double(value)
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [MessageResponse.Content.DynamicContent]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var dictionaryValue: [String: MessageResponse.Content.DynamicContent]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }
}

// MARK: - Errors

enum AIServiceError: Error, LocalizedError {
    case notConfigured
    case apiError(String)
    case noActionFound
    case invalidToolInput(tool: String, keys: [String])
    case blockNotFound
    case unknownTool(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI service is not configured. Please add your API key."
        case .apiError(let message):
            return "AI service error: \(message)"
        case .noActionFound:
            return "I couldn't understand that request. Please try rephrasing."
        case .invalidToolInput(let tool, let keys):
            return "I received invalid data for \(tool) (keys: \(keys.joined(separator: ", "))). Please try again."
        case .blockNotFound:
            return "I couldn't find the schedule block you mentioned."
        case .unknownTool(let name):
            return "Unknown action: \(name)"
        }
    }
}
