import XCTest
@testable import TearoffCore

final class DayKeyTests: XCTestCase {
    private let calendar = Calendar.current

    private func dayAgo(_ n: Int) -> String {
        DayKey.key(for: calendar.date(byAdding: .day, value: -n, to: Date())!)
    }

    func testTodayMatchesKeyForNow() {
        XCTAssertEqual(DayKey.today(), DayKey.key(for: Date()))
    }

    func testKeyFormat() {
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 7
        let date = calendar.date(from: components)!
        XCTAssertEqual(DayKey.key(for: date), "2026-03-07")
    }

    func testKeysSortChronologically() {
        XCTAssertLessThan(dayAgo(1), dayAgo(0))
        XCTAssertLessThan("2026-09-09", "2026-09-10")
    }

    func testRoundTripThroughDate() {
        let key = DayKey.today()
        XCTAssertEqual(DayKey.key(for: DayKey.date(from: key)!), key)
    }

    func testMalformedKeyReturnsNil() {
        XCTAssertNil(DayKey.date(from: "not-a-day"))
        XCTAssertNil(DayKey.date(from: "2026-09"))
    }

    func testRecentWindow() {
        let week = DayKey.recent(7)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(Set(week).count, 7, "days must be distinct")
        XCTAssertEqual(week.last, DayKey.today(), "window ends today")
        XCTAssertEqual(week.first, dayAgo(6))
        XCTAssertEqual(week, week.sorted(), "oldest first")
    }

    /// A day key must not shift when the clock crosses a DST boundary.
    func testKeyIsStableAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 29
        components.hour = 12
        let noonOnClockChangeDay = calendar.date(from: components)!
        XCTAssertEqual(DayKey.key(for: noonOnClockChangeDay, calendar: calendar), "2026-03-29")
    }
}

final class PadTests: XCTestCase {
    private let calendar = Calendar.current

    private func dayAgo(_ n: Int) -> String {
        DayKey.key(for: calendar.date(byAdding: .day, value: -n, to: Date())!)
    }

    func testFreshPad() {
        let pad = Pad(title: "Meditate", total: 21)
        XCTAssertEqual(pad.remaining, 21)
        XCTAssertTrue(pad.canTearToday)
        XCTAssertFalse(pad.tornToday)
        XCTAssertFalse(pad.isComplete)
        XCTAssertEqual(pad.streak, 0)
    }

    func testTearingTodayBlocksASecondTear() {
        let pad = Pad(title: "Meditate", total: 21, torn: [dayAgo(0)])
        XCTAssertEqual(pad.remaining, 20)
        XCTAssertTrue(pad.tornToday)
        XCTAssertFalse(pad.canTearToday)
        XCTAssertEqual(pad.streak, 1)
    }

    func testConsecutiveDaysAccumulate() {
        let pad = Pad(title: "Run", total: 30, torn: [dayAgo(2), dayAgo(1), dayAgo(0)])
        XCTAssertEqual(pad.streak, 3)
    }

    /// The streak survives until you actually miss a day, not from midnight onwards.
    func testStreakEndingYesterdayStillCounts() {
        let pad = Pad(title: "Run", total: 30, torn: [dayAgo(3), dayAgo(2), dayAgo(1)])
        XCTAssertEqual(pad.streak, 3)
        XCTAssertTrue(pad.canTearToday)
    }

    func testGapBreaksStreak() {
        let pad = Pad(title: "Run", total: 30, torn: [dayAgo(9), dayAgo(8), dayAgo(1), dayAgo(0)])
        XCTAssertEqual(pad.streak, 2)
    }

    func testStaleStreakIsZero() {
        let pad = Pad(title: "Run", total: 30, torn: [dayAgo(5), dayAgo(4)])
        XCTAssertEqual(pad.streak, 0)
    }

    func testCompletion() {
        let pad = Pad(title: "Sprint", total: 2, torn: [dayAgo(1), dayAgo(0)])
        XCTAssertTrue(pad.isComplete)
        XCTAssertFalse(pad.canTearToday)
        XCTAssertEqual(pad.remaining, 0)
    }

    func testRemainingNeverGoesNegative() {
        let pad = Pad(title: "Overrun", total: 1, torn: [dayAgo(2), dayAgo(1), dayAgo(0)])
        XCTAssertEqual(pad.remaining, 0)
        XCTAssertTrue(pad.isComplete)
    }

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let library = Library(
            pads: [Pad(title: "Write", total: 66, torn: [dayAgo(1)], size: .large, paper: .sky,
                       originX: 12.5, originY: 900)],
            settings: AppSettings(alwaysOnTop: true, padsHidden: false)
        )
        let restored = try decoder.decode(Library.self, from: encoder.encode(library))

        XCTAssertEqual(restored.pads.first?.title, "Write")
        XCTAssertEqual(restored.pads.first?.size, .large)
        XCTAssertEqual(restored.pads.first?.paper, .sky)
        XCTAssertEqual(restored.pads.first?.originX, 12.5)
        XCTAssertEqual(restored.pads.first?.originY, 900)
        XCTAssertEqual(restored.pads.first?.torn, [dayAgo(1)])
        XCTAssertTrue(restored.settings.alwaysOnTop)
    }

    /// Older files must keep opening as the format grows.
    func testDecodesMinimalHandWrittenJSON() throws {
        let json = """
        {"pads":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"Legacy","total":10,
        "torn":[],"createdAt":"2026-01-01T00:00:00Z","size":"small","paper":"cream"}],
        "settings":{"alwaysOnTop":false,"padsHidden":false}}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(Library.self, from: Data(json.utf8))
        XCTAssertEqual(library.pads.first?.title, "Legacy")
        XCTAssertNil(library.pads.first?.originX)
    }
}
