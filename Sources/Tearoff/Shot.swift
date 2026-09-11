import SwiftUI
import AppKit
import TearoffCore

/// Screenshot generator for the README, so the pictures in the repo are reproducible and
/// never contain anyone's real goals.
///
///     TEAROFF_SHOT=docs/pads.png swift run -c release Tearoff
///
/// Renders a fixed set of demo pads offscreen and exits. `TEAROFF_SHOT_COMPOSER` does the
/// same for the New Pad window (AppKit controls render as placeholders — expected).
enum Shot {
    @MainActor
    static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment

        if let path = environment["TEAROFF_SHOT_COMPOSER"] {
            write(ComposerView(editing: nil, dismiss: {}).environmentObject(fixtureStore()), to: path)
            return true
        }

        guard let path = environment["TEAROFF_SHOT"] else { return false }
        let store = fixtureStore()
        let view = HStack(alignment: .top, spacing: 10) {
            ForEach(store.pads) { pad in
                PadView(padID: pad.id, ref: WindowRef())
                    .environmentObject(store)
                    .frame(width: pad.size.padWidth + 32,
                           height: pad.size.headerHeight + pad.size.sheetHeight + 32)
            }
        }
        .padding(28)
        .background(
            LinearGradient(colors: [Color(red: 0.30, green: 0.29, blue: 0.28),
                                    Color(red: 0.13, green: 0.13, blue: 0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        write(view, to: path)
        return true
    }

    /// Demo pads in a throwaway location — never the real library.
    private static func fixtureStore() -> Store {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tearoff-shot-\(UUID().uuidString)/pads.json")
        let store = Store(fileURL: url, watchesDayChanges: false)

        func daysAgo(_ offsets: [Int]) -> [String] {
            let calendar = Calendar.current
            return offsets.sorted(by: >).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: Date()).map { DayKey.key(for: $0) }
            }
        }

        store.add(Pad(title: "Meditate 20 min", total: 21, torn: daysAgo([6, 5, 4, 3, 1, 0]),
                      size: .medium, paper: .cream))
        store.add(Pad(title: "No sugar", total: 10, torn: daysAgo([3, 2]),
                      size: .small, paper: .sage))
        store.add(Pad(title: "Ship one thing", total: 30, torn: daysAgo([2, 1]),
                      size: .large, paper: .graphite))
        store.add(Pad(title: "Cold shower", total: 7, torn: daysAgo([6, 5, 4, 3, 2, 1, 0]),
                      size: .small, paper: .blush))
        return store
    }

    @MainActor
    private static func write(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("shot failed\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("shot → \(path)")
    }
}
