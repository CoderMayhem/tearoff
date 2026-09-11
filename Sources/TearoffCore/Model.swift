import Foundation

// MARK: - Day keys

/// Habit tracking happens in local calendar days, not in elapsed 24-hour periods.
/// A day is identified by its `"yyyy-MM-dd"` key, which sorts and compares as a string.
public enum DayKey {
    public static func key(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func today(calendar: Calendar = .current) -> String {
        key(for: Date(), calendar: calendar)
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c)
    }

    /// Keys for the last `n` days, oldest first, ending today.
    public static func recent(_ n: Int, from date: Date = Date(), calendar: Calendar = .current) -> [String] {
        let start = calendar.startOfDay(for: date)
        return (0..<n).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: start).map { key(for: $0, calendar: calendar) }
        }
    }
}

// MARK: - Pad

public enum PadSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

public enum PaperStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case cream, sand, sage, sky, blush, graphite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cream: return "Cream"
        case .sand: return "Sand"
        case .sage: return "Sage"
        case .sky: return "Sky"
        case .blush: return "Blush"
        case .graphite: return "Graphite"
        }
    }
}

/// One goal: a stack of `total` sheets, one of which you may tear off per day.
public struct Pad: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var total: Int
    /// Day keys on which a sheet was torn, oldest first.
    public var torn: [String]
    public var createdAt: Date
    public var size: PadSize
    public var paper: PaperStyle
    /// Bottom-left origin of the pad's window, in screen coordinates.
    public var originX: Double?
    public var originY: Double?

    public init(id: UUID = UUID(),
                title: String,
                total: Int,
                torn: [String] = [],
                createdAt: Date = Date(),
                size: PadSize = .medium,
                paper: PaperStyle = .cream,
                originX: Double? = nil,
                originY: Double? = nil) {
        self.id = id
        self.title = title
        self.total = total
        self.torn = torn
        self.createdAt = createdAt
        self.size = size
        self.paper = paper
        self.originX = originX
        self.originY = originY
    }

    public var remaining: Int { max(0, total - torn.count) }
    public var isComplete: Bool { torn.count >= total }
    public var tornToday: Bool { torn.last == DayKey.today() }
    public var canTearToday: Bool { !isComplete && !tornToday }

    /// Consecutive days ending today — or ending yesterday, so that a streak survives
    /// until the day you actually miss, rather than expiring at midnight.
    public var streak: Int {
        guard !torn.isEmpty else { return 0 }
        let done = Set(torn)
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: Date())
        if !done.contains(DayKey.key(for: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
            if !done.contains(DayKey.key(for: cursor)) { return 0 }
        }
        var count = 0
        while done.contains(DayKey.key(for: cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

// MARK: - Settings and file format

public struct AppSettings: Codable, Equatable, Sendable {
    /// Pads sit on the desktop, behind app windows, when false; above everything when true.
    public var alwaysOnTop: Bool
    public var padsHidden: Bool

    public init(alwaysOnTop: Bool = false, padsHidden: Bool = false) {
        self.alwaysOnTop = alwaysOnTop
        self.padsHidden = padsHidden
    }
}

/// The on-disk document: everything Tearoff knows.
public struct Library: Codable, Sendable {
    public var pads: [Pad]
    public var settings: AppSettings

    public init(pads: [Pad] = [], settings: AppSettings = AppSettings()) {
        self.pads = pads
        self.settings = settings
    }
}
