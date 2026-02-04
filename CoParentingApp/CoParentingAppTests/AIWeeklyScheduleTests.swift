import XCTest
import SwiftAnthropic
@testable import CoParentingApp

final class AIWeeklyScheduleTests: XCTestCase {

    private let service = AIScheduleService()

    // MARK: - Multi-Tool-Use Response Parsing

    func testParseMultiToolUseResponse() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let day1 = today
        let day2 = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let day1String = formatter.string(from: day1)
        let day2String = formatter.string(from: day2)

        // Existing blocks to clear
        let existingBlocks = [
            TimeBlock(date: day1, startSlot: 32, endSlot: 48, provider: .parentA),
            TimeBlock(date: day1, startSlot: 48, endSlot: 72, provider: .nanny),
            TimeBlock(date: day2, startSlot: 32, endSlot: 48, provider: .parentB),
        ]

        let response = try makeMockResponse(content: [
            makeTextContent("I'll set up the weekly schedule for you."),
            try makeToolUseContent(name: "clear_day", input: [
                "date": day1String,
                "explanation": "Clearing Monday"
            ]),
            try makeToolUseContent(name: "set_day_schedule", input: [
                "date": day1String,
                "blocks": [
                    ["provider": "parent_a", "start_slot": 28, "end_slot": 78] as [String: Any]
                ],
                "explanation": "Parent A has Monday 7am-7:30pm"
            ]),
            try makeToolUseContent(name: "clear_day", input: [
                "date": day2String,
                "explanation": "Clearing Tuesday"
            ]),
            try makeToolUseContent(name: "set_day_schedule", input: [
                "date": day2String,
                "blocks": [
                    ["provider": "parent_b", "start_slot": 28, "end_slot": 78] as [String: Any]
                ],
                "explanation": "Parent B has Tuesday 7am-7:30pm"
            ]),
        ])

        let batch = try service.parseResponse(
            response,
            originalCommand: "Set up weekly schedule",
            currentBlocks: existingBlocks
        )

        XCTAssertEqual(batch.originalCommand, "Set up weekly schedule")
        XCTAssertFalse(batch.summary.isEmpty)

        // Clear day 1: 2 removes (parentA + nanny)
        // Set day 1: 1 add (parentA)
        // Clear day 2: 1 remove (parentB)
        // Set day 2: 1 add (parentB)
        XCTAssertEqual(batch.changeCount, 5)

        let (toSave, toDelete) = batch.applyAll()
        XCTAssertEqual(toSave.count, 2)
        XCTAssertEqual(toDelete.count, 3)
    }

    func testParseSingleToolResponseAsOneBatch() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: today)

        let response = try makeMockResponse(content: [
            makeTextContent("Moving your block to 8:15 AM."),
            try makeToolUseContent(name: "add_block", input: [
                "date": dateString,
                "provider": "nanny",
                "start_slot": 36,
                "end_slot": 60,
                "explanation": "Adding nanny 9am-3pm"
            ])
        ])

        let batch = try service.parseResponse(
            response,
            originalCommand: "Add nanny 9am-3pm today",
            currentBlocks: []
        )

        XCTAssertEqual(batch.changeCount, 1)
        XCTAssertEqual(batch.changes[0].changeType, .addBlock)
        XCTAssertEqual(batch.changes[0].proposedBlock?.provider, .nanny)
        XCTAssertEqual(batch.changes[0].proposedBlock?.startSlot, 36)
        XCTAssertEqual(batch.changes[0].proposedBlock?.endSlot, 60)
    }

    func testNoToolUseThrows() throws {
        let response = try makeMockResponse(content: [
            makeTextContent("I'm not sure what you mean.")
        ])

        XCTAssertThrowsError(
            try service.parseResponse(response, originalCommand: "blah", currentBlocks: [])
        ) { error in
            XCTAssertTrue(error is AIServiceError)
            if case AIServiceError.noActionFound = error { } else {
                XCTFail("Expected noActionFound, got \(error)")
            }
        }
    }

    // MARK: - Single-Day Override Scenario

    func testSingleDayOverrideScenario() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: today)

        let existingBlocks = [
            TimeBlock(date: today, startSlot: 32, endSlot: 48, provider: .parentA),
            TimeBlock(date: today, startSlot: 48, endSlot: 72, provider: .parentB),
        ]

        let response = try makeMockResponse(content: [
            makeTextContent("I'll replace parent B's block with a nanny block."),
            try makeToolUseContent(name: "clear_day", input: [
                "date": dateString,
                "provider": "parent_b",
                "explanation": "Removing parent B's block"
            ]),
            try makeToolUseContent(name: "set_day_schedule", input: [
                "date": dateString,
                "blocks": [
                    ["provider": "nanny", "start_slot": 36, "end_slot": 60] as [String: Any]
                ],
                "explanation": "Adding nanny 9am-3pm"
            ]),
        ])

        let batch = try service.parseResponse(
            response,
            originalCommand: "Have nanny cover 9-3 instead of parent B",
            currentBlocks: existingBlocks
        )

        // 1 remove (parent B) + 1 add (nanny)
        XCTAssertEqual(batch.changeCount, 2)

        let (toSave, toDelete) = batch.applyAll()
        XCTAssertEqual(toSave.count, 1)
        XCTAssertEqual(toDelete.count, 1)
        XCTAssertEqual(toSave[0].provider, .nanny)
        XCTAssertEqual(toDelete[0].provider, .parentB)
    }

    // MARK: - Date-Range Override Scenario

    func testDateRangeOverrideScenario() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var existingBlocks: [TimeBlock] = []
        var contentItems: [Any] = [["type": "text", "text": "I'll update Mon-Wed for parent B."]]

        for dayOffset in 0..<3 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            let ds = formatter.string(from: date)

            existingBlocks.append(TimeBlock(date: date, startSlot: 32, endSlot: 72, provider: .parentA))

            contentItems.append([
                "type": "tool_use",
                "id": "clear_\(dayOffset)",
                "name": "clear_day",
                "input": ["date": ds, "explanation": "Clearing day \(dayOffset)"]
            ] as [String: Any])
            contentItems.append([
                "type": "tool_use",
                "id": "set_\(dayOffset)",
                "name": "set_day_schedule",
                "input": [
                    "date": ds,
                    "blocks": [
                        ["provider": "parent_b", "start_slot": 28, "end_slot": 78] as [String: Any]
                    ],
                    "explanation": "Parent B takes over"
                ] as [String: Any]
            ] as [String: Any])
        }

        let responseDict: [String: Any] = [
            "id": "msg_test",
            "type": "message",
            "model": "claude-sonnet-4-5-20250929",
            "role": "assistant",
            "content": contentItems,
            "stopReason": "end_turn",
            "usage": ["inputTokens": 100, "outputTokens": 200]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseDict)
        let response = try JSONDecoder().decode(MessageResponse.self, from: data)

        let batch = try service.parseResponse(
            response,
            originalCommand: "Parent B takes Mon-Wed",
            currentBlocks: existingBlocks
        )

        // 3 clear_day (1 block each = 3 removes) + 3 set_day_schedule (1 block each = 3 adds) = 6
        XCTAssertEqual(batch.changeCount, 6)

        let (toSave, toDelete) = batch.applyAll()
        XCTAssertEqual(toSave.count, 3)
        XCTAssertEqual(toDelete.count, 3)

        for block in toSave {
            XCTAssertEqual(block.provider, .parentB)
            XCTAssertEqual(block.startSlot, 28)
            XCTAssertEqual(block.endSlot, 78)
        }
    }

    // MARK: - Summary Extraction

    func testSummaryFromTextBlock() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let response = try makeMockResponse(content: [
            makeTextContent("Here's your updated schedule."),
            try makeToolUseContent(name: "add_block", input: [
                "date": formatter.string(from: today),
                "provider": "nanny",
                "start_slot": 36,
                "end_slot": 60,
                "explanation": "Adding nanny"
            ])
        ])

        let batch = try service.parseResponse(response, originalCommand: "test", currentBlocks: [])
        XCTAssertEqual(batch.summary, "Here's your updated schedule.")
    }

    func testSummaryFallbackWhenNoText() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let response = try makeMockResponse(content: [
            try makeToolUseContent(name: "add_block", input: [
                "date": formatter.string(from: today),
                "provider": "nanny",
                "start_slot": 36,
                "end_slot": 60,
                "explanation": "Adding nanny"
            ])
        ])

        let batch = try service.parseResponse(response, originalCommand: "test", currentBlocks: [])
        XCTAssertEqual(batch.summary, "1 schedule change")
    }

    // MARK: - Helpers

    private func makeTextContent(_ text: String) -> Any {
        return ["type": "text", "text": text] as [String: Any]
    }

    private func makeToolUseContent(name: String, input: [String: Any]) throws -> Any {
        return [
            "type": "tool_use",
            "id": "tool_\(name)_\(UUID().uuidString.prefix(8))",
            "name": name,
            "input": input
        ] as [String: Any]
    }

    private func makeMockResponse(content: [Any]) throws -> MessageResponse {
        let responseDict: [String: Any] = [
            "id": "msg_test",
            "type": "message",
            "model": "claude-sonnet-4-5-20250929",
            "role": "assistant",
            "content": content,
            "stopReason": "end_turn",
            "usage": ["inputTokens": 100, "outputTokens": 200]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseDict)
        return try JSONDecoder().decode(MessageResponse.self, from: data)
    }
}
