import XCTest
@testable import TearoffCore

final class StoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tearoff-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("pads.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> Store {
        Store(fileURL: fileURL, watchesDayChanges: false)
    }

    func testStartsEmpty() {
        XCTAssertTrue(makeStore().pads.isEmpty)
    }

    func testAddAndLookUp() {
        let store = makeStore()
        let pad = store.add(Pad(title: "Meditate", total: 21))
        XCTAssertEqual(store.pads.count, 1)
        XCTAssertEqual(store.pad(pad.id)?.title, "Meditate")
        XCTAssertNil(store.pad(UUID()))
    }

    func testTearOncePerDay() {
        let store = makeStore()
        let pad = store.add(Pad(title: "Meditate", total: 21))

        XCTAssertTrue(store.tear(pad.id), "first tear of the day succeeds")
        XCTAssertEqual(store.pad(pad.id)?.remaining, 20)

        XCTAssertFalse(store.tear(pad.id), "a second tear on the same day is refused")
        XCTAssertEqual(store.pad(pad.id)?.remaining, 20)
        XCTAssertEqual(store.pad(pad.id)?.torn, [DayKey.today()])
    }

    func testTearOnFinishedPadIsRefused() {
        let store = makeStore()
        let yesterday = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let pad = store.add(Pad(title: "Sprint", total: 1, torn: [yesterday]))
        XCTAssertFalse(store.tear(pad.id))
        XCTAssertEqual(store.pad(pad.id)?.torn.count, 1)
    }

    func testUndoRemovesOnlyTodaysTear() {
        let store = makeStore()
        let yesterday = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let pad = store.add(Pad(title: "Meditate", total: 21, torn: [yesterday]))

        XCTAssertFalse(store.undoToday(pad.id), "nothing torn today, nothing to undo")

        store.tear(pad.id)
        XCTAssertTrue(store.undoToday(pad.id))
        XCTAssertEqual(store.pad(pad.id)?.torn, [yesterday], "yesterday's record survives")

        XCTAssertFalse(store.undoToday(pad.id), "undo cannot reach back past today")
    }

    func testResetClearsHistoryButKeepsThePad() {
        let store = makeStore()
        let pad = store.add(Pad(title: "Meditate", total: 21, size: .large, paper: .sage))
        store.tear(pad.id)
        store.reset(pad.id)

        XCTAssertEqual(store.pad(pad.id)?.remaining, 21)
        XCTAssertEqual(store.pad(pad.id)?.size, .large)
        XCTAssertEqual(store.pad(pad.id)?.paper, .sage)
        XCTAssertTrue(store.pad(pad.id)!.canTearToday)
    }

    func testRemove() {
        let store = makeStore()
        let keep = store.add(Pad(title: "Keep", total: 10))
        let drop = store.add(Pad(title: "Drop", total: 10))
        store.remove(drop.id)
        XCTAssertEqual(store.pads.map(\.id), [keep.id])
    }

    func testUpdateMutatesInPlace() {
        let store = makeStore()
        let pad = store.add(Pad(title: "Old", total: 10))
        store.update(pad.id) { $0.title = "New"; $0.total = 30 }
        XCTAssertEqual(store.pad(pad.id)?.title, "New")
        XCTAssertEqual(store.pad(pad.id)?.total, 30)
    }

    func testSetOrigin() {
        let store = makeStore()
        let pad = store.add(Pad(title: "Move me", total: 10))
        store.setOrigin(pad.id, x: 120.5, y: 640)
        XCTAssertEqual(store.pad(pad.id)?.originX, 120.5)
        XCTAssertEqual(store.pad(pad.id)?.originY, 640)
    }

    func testPersistsAcrossInstances() {
        let store = makeStore()
        let pad = store.add(Pad(title: "Meditate", total: 21, size: .small, paper: .blush))
        store.tear(pad.id)
        store.setOrigin(pad.id, x: 40, y: 800)
        store.settings.alwaysOnTop = true
        store.saveNow()

        let reopened = makeStore()
        XCTAssertEqual(reopened.pads.count, 1)
        let restored = reopened.pads[0]
        XCTAssertEqual(restored.id, pad.id)
        XCTAssertEqual(restored.title, "Meditate")
        XCTAssertEqual(restored.torn, [DayKey.today()])
        XCTAssertEqual(restored.size, .small)
        XCTAssertEqual(restored.paper, .blush)
        XCTAssertEqual(restored.originX, 40)
        XCTAssertTrue(reopened.settings.alwaysOnTop)
    }

    func testWritesAreValidJSON() throws {
        let store = makeStore()
        store.add(Pad(title: "Meditate", total: 21))
        store.saveNow()

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        XCTAssertNotNil(object?["pads"])
        XCTAssertNotNil(object?["settings"])
    }

    /// An unreadable file is moved aside, never overwritten in place.
    func testCorruptFileIsPreserved() throws {
        try Data("this is not json".utf8).write(to: fileURL)

        let store = makeStore()
        XCTAssertTrue(store.pads.isEmpty, "a bad file yields an empty library, not a crash")

        let backup = fileURL.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "this is not json")

        store.add(Pad(title: "Fresh start", total: 7))
        store.saveNow()
        XCTAssertEqual(makeStore().pads.count, 1)
    }

    func testMissingFileIsNotAnError() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let store = makeStore()
        XCTAssertTrue(store.pads.isEmpty)
        store.add(Pad(title: "First", total: 21))
        store.saveNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
