import AppKit
import SwiftUI
import TearoffCore

extension Pad {
    /// Saved bottom-left window origin, in screen coordinates.
    var origin: CGPoint? {
        guard let x = originX, let y = originY else { return nil }
        return CGPoint(x: x, y: y)
    }
}

extension Store {
    func setOrigin(_ id: UUID, _ point: CGPoint) {
        setOrigin(id, x: Double(point.x), y: Double(point.y))
    }
}

/// Borderless, non-activating panel: clicking a pad never steals focus from your work.
final class PadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Clicks in the transparent shadow margin fall through to whatever is behind the pad.
final class PassthroughView: NSView {
    var margin: CGFloat = 16

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.insetBy(dx: margin, dy: margin).contains(local) ? super.hitTest(point) : nil
    }
}

enum PadLayer {
    /// Pads stay on the one desktop they were placed on: no `canJoinAllSpaces` (that put them
    /// on every Space) and no `fullScreenAuxiliary` (that drew them over full-screen apps).
    /// `.fullScreenNone` is deliberately absent — it stops the panel appearing at all.
    static let behavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]

    /// Above the wallpaper and desktop icons, below every app window.
    static let desktop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    static let floating = NSWindow.Level.floating
}

extension NSWindow {
    static func makePad(for pad: Pad, store: Store, ref: WindowRef) -> PadPanel {
        let size = NSSize(width: pad.size.padWidth + 32,
                          height: pad.size.headerHeight + pad.size.sheetHeight + 32)
        let panel = PadPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false           // the pad draws its own, so it can move during a tear
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = PadLayer.behavior

        let container = PassthroughView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: PadView(padID: pad.id, ref: ref).environmentObject(store))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        ref.window = panel
        return panel
    }
}
