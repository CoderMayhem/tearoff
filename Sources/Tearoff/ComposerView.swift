import SwiftUI
import TearoffCore

struct ComposerView: View {
    let editing: UUID?
    let dismiss: () -> Void
    @EnvironmentObject var store: Store

    @State private var title: String = ""
    @State private var total: Int = 21
    @State private var customTotal: String = ""
    @State private var size: PadSize = .medium
    @State private var paper: PaperStyle = .cream
    @State private var loaded = false
    @FocusState private var titleFocused: Bool

    private let presets = [7, 10, 21, 30, 66, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Goal")
                TextField("Meditate 20 minutes", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($titleFocused)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Days")
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { n in
                        Button {
                            total = n
                            customTotal = ""
                        } label: {
                            Text("\(n)")
                                .font(.system(size: 12, weight: total == n ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(total == n ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(total == n ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
                        )
                    }
                    TextField("other", text: $customTotal)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 54)
                        .onChange(of: customTotal) { _, value in
                            if let n = Int(value), n > 0 { total = min(n, 999) }
                        }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Size")
                        Picker("", selection: $size) {
                            ForEach(PadSize.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Paper")
                        HStack(spacing: 7) {
                            ForEach(PaperStyle.allCases) { style in
                                let p = PaperPalette.palette(for: style)
                                Circle()
                                    .fill(p.sheet)
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.accentColor, lineWidth: 2)
                                            .padding(-3)
                                            .opacity(paper == style ? 1 : 0)
                                    )
                                    .onTapGesture { paper = style }
                                    .help(style.label)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                PadPreview(title: title.isEmpty ? "Your goal" : title, number: total, paper: paper)
                    .frame(width: 108)
            }

            Spacer(minLength: 0)

            HStack {
                if editing != nil {
                    Text("\(store.pad(editing!)?.torn.count ?? 0) days already recorded")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create Pad" : "Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380, height: 404)
        .onAppear {
            loadIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { titleFocused = true }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let id = editing, let pad = store.pad(id) {
            title = pad.title
            total = pad.total
            size = pad.size
            paper = pad.paper
            if !presets.contains(pad.total) { customTotal = "\(pad.total)" }
        }
    }

    private func commit() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let id = editing, let existing = store.pad(id) {
            store.update(id) { pad in
                pad.title = clean
                pad.total = max(total, existing.torn.count)
                pad.size = size
                pad.paper = paper
            }
            AppController.shared.resizeWindow(for: id)
        } else {
            store.add(Pad(title: clean, total: total, size: size, paper: paper))
        }
        dismiss()
    }
}

/// Static miniature of the pad, for the composer.
struct PadPreview: View {
    let title: String
    let number: Int
    let paper: PaperStyle

    var body: some View {
        let p = PaperPalette.palette(for: paper)
        VStack(spacing: 0) {
            ZStack {
                p.board
                VStack(spacing: 3) {
                    HStack(spacing: 22) {
                        ForEach(0..<2, id: \.self) { _ in
                            Circle().fill(Color.black.opacity(0.55)).frame(width: 4, height: 4)
                        }
                    }
                    Text(title)
                        .font(.label(8, weight: .semibold))
                        .kerning(1.1)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .foregroundStyle(p.boardInk.opacity(0.92))
                        .padding(.horizontal, 6)
                }
                .padding(.top, 3)
            }
            .frame(height: 30)

            ZStack {
                p.sheet
                VStack(spacing: 2) {
                    Text("\(number)")
                        .font(.numeral(40))
                        .foregroundStyle(p.ink)
                    Text("days to go")
                        .font(.label(6, weight: .medium))
                        .kerning(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(p.ink.opacity(0.45))
                }
            }
            .frame(height: 118)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
        .padding(.top, 18)
    }
}
