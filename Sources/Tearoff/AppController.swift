import AppKit
import SwiftUI
import Combine
import ServiceManagement
import TearoffCore

/// Owns the pad windows, the menu-bar item and the composer window.
final class AppController: NSObject, NSMenuDelegate {
    static let shared = AppController()

    private let store = Store.shared
    private var windows: [UUID: PadPanel] = [:]
    private var refs: [UUID: WindowRef] = [:]
    private var cancellables = Set<AnyCancellable>()

    private var statusItem: NSStatusItem?
    private var composer: NSWindow?
    private var nextCascade: Int = 0

    // MARK: - Lifecycle

    func start() {
        buildStatusItem()
        syncWindows()

        store.$pads
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncWindows() }
            .store(in: &cancellables)

        store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in self?.applySettings(settings) }
            .store(in: &cancellables)

        store.$pads
            .receive(on: RunLoop.main)
            .sink { [weak self] pads in self?.updateBadge(pads) }
            .store(in: &cancellables)

        store.$today
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateBadge(self?.store.pads ?? []) }
            .store(in: &cancellables)

        updateBadge(store.pads)

        if store.pads.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.newPad()
            }
        }
    }

    // MARK: - Windows

    private func syncWindows() {
        let live = Set(store.pads.map(\.id))

        for (id, window) in windows where !live.contains(id) {
            window.orderOut(nil)
            window.close()
            windows[id] = nil
            refs[id] = nil
        }

        for pad in store.pads where windows[pad.id] == nil {
            let ref = WindowRef()
            let panel = NSWindow.makePad(for: pad, store: store, ref: ref)
            refs[pad.id] = ref
            windows[pad.id] = panel
            let origin = pad.origin.flatMap { isVisible($0, size: panel.frame.size) ? $0 : nil }
            panel.setFrameOrigin(origin ?? cascadeOrigin(for: panel))
            if origin == nil { store.setOrigin(pad.id, panel.frame.origin) }
            applyLevel(to: panel)
            if !store.settings.padsHidden { panel.orderFront(nil) }
        }
    }

    /// True when enough of the pad would land on some attached display to be grabbable.
    private func isVisible(_ origin: CGPoint, size: NSSize) -> Bool {
        let frame = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame.insetBy(dx: 16, dy: 16)) }
    }

    private func cascadeOrigin(for window: NSWindow) -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let step = CGFloat(nextCascade % 6)
        nextCascade += 1
        let x = screen.maxX - window.frame.width - 28 - step * 22
        let y = screen.maxY - window.frame.height - 24 - step * 26
        return CGPoint(x: max(screen.minX + 8, x), y: max(screen.minY + 8, y))
    }

    private func applyLevel(to window: NSWindow) {
        window.level = store.settings.alwaysOnTop ? PadLayer.floating : PadLayer.desktop
    }

    private func applySettings(_ settings: AppSettings) {
        for window in windows.values {
            window.level = settings.alwaysOnTop ? PadLayer.floating : PadLayer.desktop
            if settings.padsHidden { window.orderOut(nil) } else { window.orderFront(nil) }
        }
    }

    /// Keeps the pad's top-left corner pinned when its size changes.
    func resizeWindow(for id: UUID) {
        guard let pad = store.pad(id), let window = windows[id] else { return }
        let newSize = NSSize(width: pad.size.padWidth + 32,
                             height: pad.size.headerHeight + pad.size.sheetHeight + 32)
        let old = window.frame
        let origin = CGPoint(x: old.minX, y: old.maxY - newSize.height)
        window.setFrame(NSRect(origin: origin, size: newSize), display: true)
        store.setOrigin(id, origin)
    }

    /// Briefly lifts a pad above everything so you can find it.
    func locate(_ id: UUID) {
        guard let window = windows[id] else { return }
        window.level = PadLayer.floating
        window.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            window.collectionBehavior.remove(.moveToActiveSpace)
        }
        let flash = {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 0.35
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    window.animator().alphaValue = 1
                }
            }
        }
        flash()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: flash)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self else { return }
            self.applyLevel(to: window)
        }
    }

    // MARK: - Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Tearoff")
            button.image?.isTemplate = true
            button.toolTip = "Tearoff"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// The menu-bar item carries the number of pads still waiting for a tear today.
    private func updateBadge(_ pads: [Pad]) {
        guard let button = statusItem?.button else { return }
        let pending = pads.filter(\.canTearToday).count
        button.title = pending > 0 ? " \(pending)" : ""
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.toolTip = pending > 0
            ? "Tearoff — \(pending) pad\(pending == 1 ? "" : "s") to tear today"
            : "Tearoff — all caught up"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let newItem = NSMenuItem(title: "New Pad…", action: #selector(newPad), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        if !store.pads.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Pads", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for pad in store.pads {
                let status = pad.isComplete ? "complete"
                    : pad.tornToday ? "\(pad.remaining) left · done today"
                    : "\(pad.remaining) left"
                let item = NSMenuItem(title: "\(pad.title)  —  \(status)", action: nil, keyEquivalent: "")
                item.indentationLevel = 1
                if pad.canTearToday {
                    item.onStateImage = nil
                }
                let sub = NSMenu()

                if pad.canTearToday {
                    sub.addItem(action("Tear Off Today", #selector(tearFromMenu(_:)), pad.id))
                } else if pad.tornToday {
                    sub.addItem(action("Undo Today's Tear", #selector(undoFromMenu(_:)), pad.id))
                }
                sub.addItem(action("Locate Pad", #selector(locateFromMenu(_:)), pad.id))
                sub.addItem(action("Edit Goal…", #selector(editFromMenu(_:)), pad.id))
                sub.addItem(.separator())
                sub.addItem(action("Start Over", #selector(resetFromMenu(_:)), pad.id))
                sub.addItem(action("Delete Pad…", #selector(deleteFromMenu(_:)), pad.id))
                item.submenu = sub
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let onTop = NSMenuItem(title: "Keep Pads On Top", action: #selector(toggleOnTop), keyEquivalent: "")
        onTop.target = self
        onTop.state = store.settings.alwaysOnTop ? .on : .off
        menu.addItem(onTop)

        let gather = NSMenuItem(title: "Gather Pads on This Desktop", action: #selector(gatherPads), keyEquivalent: "")
        gather.target = self
        menu.addItem(gather)

        let hide = NSMenuItem(title: "Hide All Pads", action: #selector(toggleHidden), keyEquivalent: "")
        hide.target = self
        hide.state = store.settings.padsHidden ? .on : .off
        menu.addItem(hide)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Tearoff", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func action(_ title: String, _ selector: Selector, _ id: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        return item
    }

    private func padID(from sender: Any?) -> UUID? {
        (sender as? NSMenuItem)?.representedObject as? UUID
    }

    // MARK: - Menu actions

    @objc private func tearFromMenu(_ sender: Any?) {
        guard let id = padID(from: sender) else { return }
        store.tear(id)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    @objc private func undoFromMenu(_ sender: Any?) {
        guard let id = padID(from: sender) else { return }
        store.undoToday(id)
    }

    @objc private func locateFromMenu(_ sender: Any?) {
        guard let id = padID(from: sender) else { return }
        if store.settings.padsHidden { store.settings.padsHidden = false }
        locate(id)
    }

    @objc private func editFromMenu(_ sender: Any?) {
        guard let id = padID(from: sender) else { return }
        editPad(id)
    }

    @objc private func resetFromMenu(_ sender: Any?) {
        guard let id = padID(from: sender) else { return }
        confirmReset(id)
    }

    @objc private func deleteFromMenu(_ sender: Any?) {
        guard let id = padID(from: sender) else { return }
        confirmDelete(id)
    }

    /// Pads stay on the desktop they were placed on. This drags them all to the desktop
    /// you are looking at now — the way back if one ends up on a Space you no longer use.
    @objc private func gatherPads() {
        if store.settings.padsHidden { store.settings.padsHidden = false }
        NSApp.activate(ignoringOtherApps: true)
        for (id, window) in windows {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.orderFrontRegardless()
            if !isVisible(window.frame.origin, size: window.frame.size) {
                let origin = cascadeOrigin(for: window)
                window.setFrameOrigin(origin)
                store.setOrigin(id, origin)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            for (id, window) in self.windows {
                window.collectionBehavior.remove(.moveToActiveSpace)
                self.store.setOrigin(id, window.frame.origin)
            }
        }
    }

    @objc private func toggleOnTop() { store.settings.alwaysOnTop.toggle() }

    @objc private func toggleHidden() { store.settings.padsHidden.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func quit() {
        store.saveNow()
        NSApp.terminate(nil)
    }

    // MARK: - Composer + confirmations

    @objc func newPad() { openComposer(editing: nil) }

    func editPad(_ id: UUID) { openComposer(editing: id) }

    private func openComposer(editing id: UUID?) {
        composer?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 404),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = id == nil ? "New Pad" : "Edit Pad"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal
        let view = ComposerView(editing: id) { [weak self] in
            self?.composer?.close()
            self?.composer = nil
        }
        window.contentView = NSHostingView(rootView: view.environmentObject(store))
        composer = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func confirmReset(_ id: UUID) {
        guard let pad = store.pad(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Start “\(pad.title)” over?"
        alert.informativeText = "The pad goes back to \(pad.total) sheets and \(pad.torn.count) recorded day\(pad.torn.count == 1 ? "" : "s") will be cleared."
        alert.addButton(withTitle: "Start Over")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { store.reset(id) }
    }

    func confirmDelete(_ id: UUID) {
        guard let pad = store.pad(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(pad.title)”?"
        alert.informativeText = "This removes the pad and its history."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { store.remove(id) }
    }
}
