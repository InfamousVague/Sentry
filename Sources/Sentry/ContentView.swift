import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(SentryStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 560)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center, spacing: 6) {
                Image(nsImage: SentryApp.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.tint)
                Text("SENTRY")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                LiveDot()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(store.items.count) persistence items")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(store.scanning ? "scanning…" : "audited \(lastScanText)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(store.scanning ? Color.accentColor : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var lastScanText: String {
        guard let d = store.lastScan else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.items.isEmpty {
                    Text("No persistence items found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(store.sections, id: \.source) { section in
                            Section {
                                ForEach(section.items) { item in
                                    PersistenceRow(
                                        item: item,
                                        highlighted: store.focusedKey == item.key
                                    )
                                    .id(item.key)
                                    Divider()
                                }
                            } header: {
                                sectionHeader(section.source, count: section.items.count)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: store.focusedKey) { _, key in
                guard let key else { return }
                withAnimation { proxy.scrollTo(key, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if store.focusedKey == key { store.focusedKey = nil }
                }
            }
        }
    }

    private func sectionHeader(_ source: PersistenceSource, count: Int) -> some View {
        HStack {
            Text(source.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var footer: some View {
        HStack {
            Button {
                store.refresh()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Quit Sentry") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct PersistenceRow: View {
    let item: PersistenceItem
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            SignatureBadge(status: item.signature)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Color.accentColor.opacity(0.18) : Color.clear)
        .animation(.easeInOut(duration: 0.25), value: highlighted)
        .contentShape(Rectangle())
    }
}

private struct SignatureBadge: View {
    let status: SignatureStatus

    private var color: Color {
        switch status.color {
        case "green":  return .green
        case "yellow": return .yellow
        case "red":    return .red
        default:       return .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .help(status.label)
    }
}

private struct LiveDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .help("Live — auditing persistence every 8 seconds")
    }
}
