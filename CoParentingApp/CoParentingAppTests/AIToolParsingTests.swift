import XCTest
import SwiftAnthropic
@testable import CoParentingApp

final class AIToolParsingTests: XCTestCase {

    private let service = AIScheduleService()
    private let testDate = Calendar.current.startOfDay(for: Date())
    private lazy var dateString: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: testDate)
    }()

    // MARK: - Existing Tool Parsing

    func testParseAddBlockTool() throws {
        let toolUse = try decodeToolUse(name: "add_block", input: [
            "date": dateString,
            "provider": "parent_a",
            "start_slot": 28,
            "end_slot": 78,
            "notes": "Full day",
            "explanation": "Adding parent A for the full day"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: [])
        XCTAssertEqual(changes.count, 1)

        let change = changes[0]
        XCTAssertEqual(change.changeType, .addBlock)
        XCTAssertNotNil(change.proposedBlock)
        XCTAssertEqual(change.proposedBlock?.provider, .parentA)
        XCTAssertEqual(change.proposedBlock?.startSlot, 28)
        XCTAssertEqual(change.proposedBlock?.endSlot, 78)
        XCTAssertEqual(change.proposedBlock?.notes, "Full day")
        XCTAssertEqual(change.aiExplanation, "Adding parent A for the full day")
    }

    func testParseRemoveBlockTool() throws {
        let existingBlock = TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .nanny)

        let toolUse = try decodeToolUse(name: "remove_block", input: [
            "date": dateString,
            "provider": "nanny",
            "start_slot": 32,
            "explanation": "Removing nanny block"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: [existingBlock])
        XCTAssertEqual(changes.count, 1)

        let change = changes[0]
        XCTAssertEqual(change.changeType, .removeBlock)
        XCTAssertNotNil(change.originalBlock)
        XCTAssertEqual(change.originalBlock?.id, existingBlock.id)
    }

    func testParseChangeTimeTool() throws {
        let existingBlock = TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .parentA)

        let toolUse = try decodeToolUse(name: "change_time", input: [
            "date": dateString,
            "provider": "parent_a",
            "new_start_slot": 33,
            "new_end_slot": 49,
            "explanation": "Moving to 8:15 AM"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: [existingBlock])
        XCTAssertEqual(changes.count, 1)

        let change = changes[0]
        XCTAssertEqual(change.changeType, .changeTime)
        XCTAssertNotNil(change.originalBlock)
        XCTAssertNotNil(change.proposedBlock)
        XCTAssertEqual(change.proposedBlock?.startSlot, 33)
        XCTAssertEqual(change.proposedBlock?.endSlot, 49)
        XCTAssertEqual(change.proposedBlock?.id, existingBlock.id)
    }

    func testParseSwapDaysTool() throws {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: testDate)!
        let tomorrowString: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: tomorrow)
        }()

        let block1 = TimeBlock(date: testDate, startSlot: 32, endSlot: 72, provider: .parentA)
        let block2 = TimeBlock(date: tomorrow, startSlot: 32, endSlot: 72, provider: .parentB)

        let toolUse = try decodeToolUse(name: "swap_days", input: [
            "date1": dateString,
            "date2": tomorrowString,
            "explanation": "Swapping days"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: [block1, block2])
        XCTAssertEqual(changes.count, 1)

        let change = changes[0]
        XCTAssertEqual(change.changeType, .swap)
        XCTAssertNotNil(change.proposedBlock)
        XCTAssertNotNil(change.secondaryProposedBlock)
    }

    // MARK: - New Tool Parsing: set_day_schedule

    func testParseSetDaySchedule() throws {
        let toolUse = try decodeToolUse(name: "set_day_schedule", input: [
            "date": dateString,
            "blocks": [
                ["provider": "parent_a", "start_slot": 28, "end_slot": 48, "notes": "Morning"] as [String: Any],
                ["provider": "nanny", "start_slot": 48, "end_slot": 72] as [String: Any],
                ["provider": "parent_b", "start_slot": 72, "end_slot": 78] as [String: Any],
            ],
            "explanation": "Setting up the day schedule"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: [])
        XCTAssertEqual(changes.count, 3)

        XCTAssertEqual(changes[0].changeType, .addBlock)
        XCTAssertEqual(changes[0].proposedBlock?.provider, .parentA)
        XCTAssertEqual(changes[0].proposedBlock?.startSlot, 28)
        XCTAssertEqual(changes[0].proposedBlock?.endSlot, 48)
        XCTAssertEqual(changes[0].proposedBlock?.notes, "Morning")

        XCTAssertEqual(changes[1].proposedBlock?.provider, .nanny)
        XCTAssertEqual(changes[1].proposedBlock?.startSlot, 48)
        XCTAssertEqual(changes[1].proposedBlock?.endSlot, 72)

        XCTAssertEqual(changes[2].proposedBlock?.provider, .parentB)
        XCTAssertEqual(changes[2].proposedBlock?.startSlot, 72)
        XCTAssertEqual(changes[2].proposedBlock?.endSlot, 78)
    }

    func testParseSetDayScheduleEmptyBlocks() throws {
        let toolUse = try decodeToolUse(name: "set_day_schedule", input: [
            "date": dateString,
            "blocks": [] as [Any],
            "explanation": "Empty schedule"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: [])
        XCTAssertEqual(changes.count, 0)
    }

    // MARK: - New Tool Parsing: clear_day

    func testParseClearDayAllProviders() throws {
        let blocks = [
            TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .parentA),
            TimeBlock(date: testDate, startSlot: 48, endSlot: 72, provider: .nanny),
            TimeBlock(date: testDate, startSlot: 72, endSlot: 84, provider: .parentB),
        ]

        let toolUse = try decodeToolUse(name: "clear_day", input: [
            "date": dateString,
            "explanation": "Clearing the day"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: blocks)
        XCTAssertEqual(changes.count, 3)

        for change in changes {
            XCTAssertEqual(change.changeType, .removeBlock)
            XCTAssertNotNil(change.originalBlock)
        }
    }

    func testParseClearDaySpecificProvider() throws {
        let blocks = [
            TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .parentA),
            TimeBlock(date: testDate, startSlot: 48, endSlot: 72, provider: .nanny),
            TimeBlock(date: testDate, startSlot: 72, endSlot: 84, provider: .parentB),
        ]

        let toolUse = try decodeToolUse(name: "clear_day", input: [
            "date": dateString,
            "provider": "nanny",
            "explanation": "Clearing nanny"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: blocks)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].originalBlock?.provider, .nanny)
    }

    func testParseClearDayNoMatches() throws {
        let blocks = [
            TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .parentA),
        ]

        let otherDate = Calendar.current.date(byAdding: .day, value: 5, to: testDate)!
        let otherDateString: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: otherDate)
        }()

        let toolUse = try decodeToolUse(name: "clear_day", input: [
            "date": otherDateString,
            "explanation": "Clearing a day with no blocks"
        ])

        let changes = try service.parseToolUse(toolUse, currentBlocks: blocks)
        XCTAssertEqual(changes.count, 0)
    }

    // MARK: - Error Cases

    func testInvalidToolInputThrows() throws {
        let toolUse = try decodeToolUse(name: "add_block", input: [
            "date": dateString,
            // Missing required fields
        ])

        XCTAssertThrowsError(try service.parseToolUse(toolUse, currentBlocks: [])) { error in
            XCTAssertTrue(error is AIServiceError)
        }
    }

    func testUnknownToolThrows() throws {
        let toolUse = try decodeToolUse(name: "unknown_tool", input: [:])

        XCTAssertThrowsError(try service.parseToolUse(toolUse, currentBlocks: [])) { error in
            if case AIServiceError.unknownTool(let name) = error {
                XCTAssertEqual(name, "unknown_tool")
            } else {
                XCTFail("Expected unknownTool error, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Decode a ToolUse from JSON since ToolUse only has init(from:)
    private func decodeToolUse(
        name: String,
        input: [String: Any]
    ) throws -> MessageResponse.Content.ToolUse {
        let inputData = try JSONSerialization.data(withJSONObject: input)
        let toolUseDict: [String: Any] = [
            "type": "tool_use",
            "id": "test_\(name)",
            "name": name,
            "input": try JSONSerialization.jsonObject(with: inputData)
        ]
        let data = try JSONSerialization.data(withJSONObject: toolUseDict)

        // Decode as MessageResponse.Content, then extract the ToolUse
        let content = try JSONDecoder().decode(MessageResponse.Content.self, from: data)
        guard case .toolUse(let toolUse) = content else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected toolUse content"])
        }
        return toolUse
    }
}
