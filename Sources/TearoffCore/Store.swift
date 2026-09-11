import Foundation
import Combine

/// The single source of truth, persisted as JSON.
///
/// Pure Foundation: no AppKit, no SwiftUI, and the file location is injectable, so the
/// whole thing runs under test without touching your real pads.
public final class Store: ObservableObject {
    public static let shared = Store(fileURL: Store.defaultFileURL())

    @Published public private(set) var pads: [Pad] = []
    @Published public var settings = AppSettings() { didSet { if settings != oldValue { scheduleSave() } } }
    /// Bumped when the calendar day rolls over, so views re-evaluate "torn today".
    @Published public private(set) var today: String = DayKey.today()

    public let fileURL: URL

    private var saveWorkItem: DispatchWorkItem?
    private var dayTimer: Timer?
    private var dayObserver: NSObjectProtocol?

    /// `~/Library/Application Support/Tearoff/pads.json`
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tearoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("pads.json")
    }

    public init(fileURL: URL, watchesDayChanges: Bool = true) {
        self.fileURL = fileURL
        load()
        if watchesDayChanges { startDayWatcher() }
    }

    deinit {
        dayTimer?.invalidate()
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let library = try? decoder.decode(Library.self, from: data) else {
            // Never silently clobber something we failed to read — park it next door.
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return
        }
        pads = library.pads
        settings = library.settings
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    public func saveNow() {
        saveWorkItem?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Library(pads: pads, settings: settings)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Day rollover

    private func startDayWatcher() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshToday() }
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer

        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshToday() }
    }

    /// Re-reads the wall clock. Public so a waking app can force a check.
    public func refreshToday() {
        let now = DayKey.today()
        guard now != today else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.today = now
            self.objectWillChange.send()
        }
    }

    // MARK: - Lookup

    public func pad(_ id: UUID) -> Pad? { pads.first { $0.id == id } }

    private func index(_ id: UUID) -> Int? { pads.firstIndex { $0.id == id } }

    // MARK: - Mutations

    @discardableResult
    public func add(_ pad: Pad) -> Pad {
        pads.append(pad)
        scheduleSave()
        return pad
    }

    public func update(_ id: UUID, _ mutate: (inout Pad) -> Void) {
        guard let i = index(id) else { return }
        mutate(&pads[i])
        scheduleSave()
    }

    /// Records today's tear. Returns false when the pad was already torn today, or is finished.
    @discardableResult
    public func tear(_ id: UUID) -> Bool {
        guard let i = index(id), pads[i].canTearToday else { return false }
        pads[i].torn.append(DayKey.today())
        scheduleSave()
        return true
    }

    /// Undoes *today's* tear only. Earlier days stay honest — you cannot rewrite last week.
    @discardableResult
    public func undoToday(_ id: UUID) -> Bool {
        guard let i = index(id), pads[i].tornToday else { return false }
        pads[i].torn.removeLast()
        scheduleSave()
        return true
    }

    public func reset(_ id: UUID) {
        update(id) { $0.torn = [] }
    }

    public func remove(_ id: UUID) {
        pads.removeAll { $0.id == id }
        scheduleSave()
    }

    public func setOrigin(_ id: UUID, x: Double, y: Double) {
        guard let i = index(id) else { return }
        pads[i].originX = x
        pads[i].originY = y
        scheduleSave()
    }
}
