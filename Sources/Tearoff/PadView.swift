import SwiftUI
import AppKit
import TearoffCore

/// Lets the SwiftUI pad reach its own NSWindow without retaining it.
final class WindowRef {
    weak var window: NSWindow?
}

struct PadView: View {
    let padID: UUID
    let ref: WindowRef
    @EnvironmentObject var store: Store

    @State private var tearOffset: CGFloat = 0
    @State private var tearTilt: Double = 0
    @State private var tearFade: Double = 1
    @State private var isTearing = false
    @State private var refusalShake: CGFloat = 0
    @State private var hovering = false
    @State private var hintPulse = false

    @State private var dragAnchorMouse: CGPoint?
    @State private var dragAnchorOrigin: CGPoint?

    private let margin: CGFloat = 16

    var body: some View {
        if let pad = store.pad(padID) {
            let p = PaperPalette.palette(for: pad.paper)
            let s = pad.size

            VStack(spacing: 0) {
                board(pad, p, s)
                sheetStack(pad, p, s)
            }
            .frame(width: s.padWidth)
            .clipShape(RoundedRectangle(cornerRadius: s.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: s.corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.30), radius: hovering ? 13 : 9, x: 0, y: hovering ? 7 : 4)
            .offset(x: refusalShake)
            .padding(margin)
            .onHover { hovering = $0 }
            .contextMenu { PadMenu(padID: padID) }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    hintPulse = true
                }
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Header board

    private func board(_ pad: Pad, _ p: PaperPalette, _ s: PadSize) -> some View {
        ZStack {
            p.board
            VStack(spacing: s.headerHeight * 0.11) {
                HStack(spacing: s.padWidth * 0.20) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                            .frame(width: s.dotSize * 0.95, height: s.dotSize * 0.95)
                    }
                }
                Text(pad.title)
                    .font(.label(s.titleSize, weight: .semibold))
                    .kerning(s.titleSize * 0.16)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(p.boardInk.opacity(0.92))
                    .padding(.horizontal, 8)
            }
            .padding(.top, s.headerHeight * 0.12)
        }
        .frame(height: s.headerHeight)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .help("Drag to move · right-click for options")
    }

    // MARK: - Sheets

    private func sheetStack(_ pad: Pad, _ p: PaperPalette, _ s: PadSize) -> some View {
        let seed = UInt64(truncatingIfNeeded: pad.id.hashValue)
        let thickness = min(6, max(0, pad.remaining - 1))

        return ZStack(alignment: .top) {
            // Remaining thickness: thin edges peeking out at the bottom of the pad.
            ForEach(0..<thickness, id: \.self) { i in
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: s.corner,
                    bottomTrailingRadius: s.corner, topTrailingRadius: 0, style: .continuous
                )
                .fill(p.sheetEdge)
                .frame(height: s.sheetHeight)
                .padding(.horizontal, CGFloat(thickness - i) * 0.5)
                .offset(y: CGFloat(thickness - i) * 1.1)
            }

            // The sheet underneath — revealed as the top one is pulled away.
            sheetFace(number: pad.remaining - 1, pad: pad, p: p, s: s, seed: seed &+ 7)
                .opacity(isTearing || tearOffset > 0 ? 1 : 0)

            // Today's sheet.
            sheetFace(number: pad.remaining, pad: pad, p: p, s: s, seed: seed)
                .rotationEffect(.degrees(tearTilt), anchor: .topLeading)
                .offset(y: tearOffset)
                .opacity(tearFade)
                .gesture(tearGesture(pad))

            // Stubs of sheets already torn off, still gripped by the binding.
            if !pad.torn.isEmpty {
                TornBottomEdge(seed: seed &+ 31, depth: s.dotSize * 0.55, step: 5)
                    .fill(p.sheet)
                    .frame(height: min(CGFloat(pad.torn.count) * 0.5 + 4.5, 8))
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.black.opacity(0.12)).frame(height: 0.5)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1.5)
            }
        }
        .frame(height: s.sheetHeight)
        .clipped()
    }

    private func sheetFace(number: Int, pad: Pad, p: PaperPalette, s: PadSize, seed: UInt64) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: s.corner,
            bottomTrailingRadius: s.corner, topTrailingRadius: 0, style: .continuous
        )
        return ZStack {
            shape.fill(
                LinearGradient(
                    colors: [p.sheet, p.sheet.opacity(0.93)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            TornTopEdge(seed: seed, depth: s.dotSize * 0.7)
                .fill(p.sheet)
                .frame(height: 6)
                .frame(maxHeight: .infinity, alignment: .top)

            if number <= 0 {
                completionFace(pad, p, s)
            } else {
                countFace(number: number, pad: pad, p: p, s: s)
            }
        }
        .frame(height: s.sheetHeight)
        .overlay(alignment: .top) {
            // A faint perforation line just under the binding.
            Rectangle()
                .fill(Color.black.opacity(0.07))
                .frame(height: 0.5)
                .padding(.top, 5)
        }
    }

    private func countFace(number: Int, pad: Pad, p: PaperPalette, s: PadSize) -> some View {
        VStack(spacing: 0) {
            Text("\(number)")
                .font(.numeral(s.numeralSize))
                .foregroundStyle(p.ink)
                .shadow(color: p.ink.opacity(0.06), radius: 0.5, y: 0.5)
            Text(number == 1 ? "day to go" : "days to go")
                .font(.label(s.captionSize, weight: .medium))
                .kerning(s.captionSize * 0.22)
                .textCase(.uppercase)
                .foregroundStyle(p.ink.opacity(0.45))
                .padding(.top, s.captionSize * 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, s.captionSize * 3.6)   // optical centre, above the footer block
        .overlay(alignment: .bottom) {
            VStack(spacing: s.captionSize * 0.7) {
                weekDots(pad, p, s)
                footer(pad, p, s)
            }
            .padding(.bottom, s.captionSize * 1.2)
        }
        .padding(.horizontal, 10)
    }

    private func completionFace(_ pad: Pad, _ p: PaperPalette, _ s: PadSize) -> some View {
        VStack(spacing: s.captionSize * 0.8) {
            Spacer(minLength: 0)
            Text("\(pad.total)")
                .font(.numeral(s.numeralSize * 0.62))
                .foregroundStyle(p.ink.opacity(0.85))
            Text("days done")
                .font(.label(s.captionSize, weight: .medium))
                .kerning(s.captionSize * 0.22)
                .textCase(.uppercase)
                .foregroundStyle(p.ink.opacity(0.45))
            Text("complete")
                .font(.label(s.titleSize, weight: .bold))
                .kerning(s.titleSize * 0.28)
                .textCase(.uppercase)
                .foregroundStyle(p.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(p.accent.opacity(0.75), lineWidth: 1.5)
                )
                .rotationEffect(.degrees(-7))
                .padding(.top, s.captionSize * 0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private func weekDots(_ pad: Pad, _ p: PaperPalette, _ s: PadSize) -> some View {
        let days = DayKey.recent(7)
        let done = Set(pad.torn)
        let today = store.today
        return HStack(spacing: s.dotSize * 0.95) {
            ForEach(days, id: \.self) { day in
                let isDone = done.contains(day)
                Circle()
                    .fill(isDone ? p.accent.opacity(0.9) : p.ink.opacity(0.11))
                    .overlay(
                        Circle()
                            .strokeBorder(day == today ? (isDone ? p.accent.opacity(0.5) : p.ink.opacity(0.35)) : .clear,
                                          lineWidth: 1)
                            .padding(-2)
                    )
                    .frame(width: s.dotSize, height: s.dotSize)
            }
        }
    }

    private func footer(_ pad: Pad, _ p: PaperPalette, _ s: PadSize) -> some View {
        Group {
            if pad.tornToday {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: s.captionSize * 0.95, weight: .bold))
                    Text(pad.streak > 1 ? "\(pad.streak) day streak" : "done today")
                        .font(.label(s.captionSize, weight: .medium))
                        .kerning(s.captionSize * 0.12)
                }
                .foregroundStyle(p.accent.opacity(0.9))
            } else {
                HStack(spacing: 3) {
                    Text("pull down to tear")
                        .font(.label(s.captionSize, weight: .medium))
                        .kerning(s.captionSize * 0.12)
                    Image(systemName: "chevron.down")
                        .font(.system(size: s.captionSize * 0.9, weight: .semibold))
                }
                .foregroundStyle(p.ink.opacity(hintPulse ? 0.42 : 0.20))
            }
        }
    }

    // MARK: - Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                guard let window = ref.window else { return }
                if dragAnchorMouse == nil {
                    dragAnchorMouse = NSEvent.mouseLocation
                    dragAnchorOrigin = window.frame.origin
                }
                guard let m0 = dragAnchorMouse, let o0 = dragAnchorOrigin else { return }
                let m = NSEvent.mouseLocation
                window.setFrameOrigin(CGPoint(x: o0.x + (m.x - m0.x), y: o0.y + (m.y - m0.y)))
            }
            .onEnded { _ in
                if let window = ref.window {
                    store.setOrigin(padID, window.frame.origin)
                }
                dragAnchorMouse = nil
                dragAnchorOrigin = nil
            }
    }

    private func tearGesture(_ pad: Pad) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !isTearing else { return }
                let pull = max(0, value.translation.height)
                if pad.canTearToday {
                    tearOffset = pull
                } else {
                    // Resists: a few points of give, then nothing.
                    tearOffset = 9 * (1 - exp(-pull / 40))
                }
            }
            .onEnded { value in
                guard !isTearing else { return }
                let threshold = pad.size.sheetHeight * 0.22
                if pad.canTearToday && value.translation.height > threshold {
                    commitTear(pad)
                } else {
                    if !pad.canTearToday && value.translation.height > threshold {
                        refuse()
                    }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) { tearOffset = 0 }
                }
            }
    }

    private func commitTear(_ pad: Pad) {
        isTearing = true
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.easeIn(duration: 0.3)) {
            tearOffset = pad.size.sheetHeight * 0.85
            tearTilt = -5
            tearFade = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            store.tear(padID)
            tearOffset = 0
            tearTilt = 0
            tearFade = 1
            isTearing = false
        }
    }

    private func refuse() {
        let steps: [CGFloat] = [-5, 4, -3, 2, 0]
        for (i, dx) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                withAnimation(.easeInOut(duration: 0.05)) { refusalShake = dx }
            }
        }
    }
}

/// Right-click menu shared by the pad and the menu-bar list.
struct PadMenu: View {
    let padID: UUID
    @EnvironmentObject var store: Store

    var body: some View {
        if let pad = store.pad(padID) {
            if pad.tornToday {
                Button("Undo Today's Tear") { store.undoToday(padID) }
            }
            Button("Edit Goal…") { AppController.shared.editPad(padID) }
            Divider()
            Menu("Size") {
                ForEach(PadSize.allCases) { size in
                    Button(size.label + (pad.size == size ? "  ✓" : "")) {
                        store.update(padID) { $0.size = size }
                        AppController.shared.resizeWindow(for: padID)
                    }
                }
            }
            Menu("Paper") {
                ForEach(PaperStyle.allCases) { style in
                    Button(style.label + (pad.paper == style ? "  ✓" : "")) {
                        store.update(padID) { $0.paper = style }
                    }
                }
            }
            Divider()
            Button("Start Over") { AppController.shared.confirmReset(padID) }
            Button("Delete Pad…") { AppController.shared.confirmDelete(padID) }
        }
    }
}
