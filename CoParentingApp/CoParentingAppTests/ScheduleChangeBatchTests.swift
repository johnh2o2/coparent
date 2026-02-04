import XCTest
@testable import CoParentingApp

final class ScheduleChangeBatchTests: XCTestCase {

    private let testDate = Calendar.current.startOfDay(for: Date())

    // MARK: - Basic Properties

    func testChangeCount() {
        let changes = [
            makeAddChange(provider: .parentA, start: 28, end: 78),
            makeAddChange(provider: .parentB, start: 28, end: 78),
        ]
        let batch = ScheduleChangeBatch(changes: changes, summary: "Test", originalCommand: "test")
        XCTAssertEqual(batch.changeCount, 2)
    }

    func testEmptyBatch() {
        let batch = ScheduleChangeBatch(changes: [], summary: "Empty", originalCommand: "none")
        XCTAssertEqual(batch.changeCount, 0)
        let (toSave, toDelete) = batch.applyAll()
        XCTAssertTrue(toSave.isEmpty)
        XCTAssertTrue(toDelete.isEmpty)
    }

    // MARK: - applyAll() Tests

    func testApplyAllWithAddBlocks() {
        let changes = [
            makeAddChange(provider: .parentA, start: 28, end: 48),
            makeAddChange(provider: .parentB, start: 48, end: 78),
        ]
        let batch = ScheduleChangeBatch(changes: changes, summary: "Add two blocks", originalCommand: "test")

        let (toSave, toDelete) = batch.applyAll()
        XCTAssertEqual(toSave.count, 2)
        XCTAssertTrue(toDelete.isEmpty)

        XCTAssertEqual(toSave[0].provider, .parentA)
        XCTAssertEqual(toSave[0].startSlot, 28)
        XCTAssertEqual(toSave[0].endSlot, 48)

        XCTAssertEqual(toSave[1].provider, .parentB)
        XCTAssertEqual(toSave[1].startSlot, 48)
        XCTAssertEqual(toSave[1].endSlot, 78)
    }

    func testApplyAllWithRemoveBlocks() {
        let existingBlock = TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .parentA)
        let change = ScheduleChange(
            changeType: .removeBlock,
            originalBlock: existingBlock,
            suggestedByAI: true,
            aiExplanation: "Removing block"
        )
        let batch = ScheduleChangeBatch(changes: [change], summary: "Remove one block", originalCommand: "test")

        let (toSave, toDelete) = batch.applyAll()
        XCTAssertTrue(toSave.isEmpty)
        XCTAssertEqual(toDelete.count, 1)
        XCTAssertEqual(toDelete[0].id, existingBlock.id)
    }

    func testApplyAllMixedAddAndRemove() {
        let existingBlock = TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .parentA)

        let removeChange = ScheduleChange(
            changeType: .removeBlock,
            originalBlock: existingBlock,
            suggestedByAI: true,
            aiExplanation: "Clearing old block"
        )
        let addChange = makeAddChange(provider: .nanny, start: 36, end: 60)

        let batch = ScheduleChangeBatch(
            changes: [removeChange, addChange],
            summary: "Replace parent A with nanny",
            originalCommand: "test"
        )

        let (toSave, toDelete) = batch.applyAll()
        XCTAssertEqual(toSave.count, 1)
        XCTAssertEqual(toDelete.count, 1)
        XCTAssertEqual(toSave[0].provider, .nanny)
        XCTAssertEqual(toDelete[0].provider, .parentA)
    }

    func testApplyAllWithTimeChange() {
        let existingBlock = TimeBlock(date: testDate, startSlot: 32, endSlot: 48, provider: .parentA)
        let proposedBlock = TimeBlock(id: existingBlock.id, date: testDate, startSlot: 33, endSlot: 49, provider: .parentA)

        let change = ScheduleChange(
            changeType: .changeTime,
            originalBlock: existingBlock,
            proposedBlock: proposedBlock,
            suggestedByAI: true,
            aiExplanation: "Moving to 8:15"
        )
        let batch = ScheduleChangeBatch(changes: [change], summary: "Time change", originalCommand: "test")

        let (toSave, toDelete) = batch.applyAll()
        XCTAssertEqual(toSave.count, 1)
        XCTAssertTrue(toDelete.isEmpty)
        XCTAssertEqual(toSave[0].startSlot, 33)
        XCTAssertEqual(toSave[0].endSlot, 49)
    }

    func testApplyAllMultiDaySchedule() {
        // Simulate a weekly schedule: 5 days with clear + add
        var changes: [ScheduleChange] = []
        let calendar = Calendar.current

        for dayOffset in 0..<5 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: testDate) else { continue }

            // Remove existing
            let existing = TimeBlock(date: date, startSlot: 32, endSlot: 48, provider: .parentA)
            changes.append(ScheduleChange(
                changeType: .removeBlock,
                originalBlock: existing,
                suggestedByAI: true,
                aiExplanation: "Clearing day"
            ))

            // Add new
            let provider: CareProvider = dayOffset % 2 == 0 ? .parentA : .parentB
            changes.append(ScheduleChange(
                changeType: .addBlock,
                proposedBlock: TimeBlock(date: date, startSlot: 28, endSlot: 78, provider: provider),
                suggestedByAI: true,
                aiExplanation: "Setting up weekly schedule"
            ))
        }

        let batch = ScheduleChangeBatch(changes: changes, summary: "Weekly schedule", originalCommand: "test")

        XCTAssertEqual(batch.changeCount, 10)
        let (toSave, toDelete) = batch.applyAll()
        XCTAssertEqual(toSave.count, 5)
        XCTAssertEqual(toDelete.count, 5)
    }

    // MARK: - Equatable

    func testEquality() {
        let id = UUID()
        let batch1 = ScheduleChangeBatch(id: id, changes: [], summary: "A", originalCommand: "a")
        let batch2 = ScheduleChangeBatch(id: id, changes: [], summary: "A", originalCommand: "a")
        XCTAssertEqual(batch1, batch2)
    }

    func testInequality() {
        let batch1 = ScheduleChangeBatch(changes: [], summary: "A", originalCommand: "a")
        let batch2 = ScheduleChangeBatch(changes: [], summary: "B", originalCommand: "b")
        XCTAssertNotEqual(batch1, batch2)
    }

    // MARK: - Helpers

    private func makeAddChange(provider: CareProvider, start: Int, end: Int) -> ScheduleChange {
        ScheduleChange(
            changeType: .addBlock,
            proposedBlock: TimeBlock(date: testDate, startSlot: start, endSlot: end, provider: provider),
            suggestedByAI: true,
            aiExplanation: "Adding block"
        )
    }
}
