import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Darwin

// MARK: - Weergave

struct RowView: View {
    let item: Item
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            } else {
                Color.clear.frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 11)).opacity(0.65).lineLimit(1)
                }
            }
            Spacer()
            if item.kind == .app {
                Text(memoryText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(selected ? .white : memoryColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundColor(selected ? .white : .primary)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }

    private var memoryText: String {
        item.memoryMB >= 1024 ? String(format: "%.1f GB", item.memoryMB / 1024)
                              : String(format: "%.0f MB", item.memoryMB)
    }

    private var memoryColor: Color {
        item.memoryMB > 2048 ? .red : item.memoryMB > 800 ? .orange : .secondary
    }
}

struct ContentView: View {
    @ObservedObject var model: Model

    var body: some View {
        let items = model.visible
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                tab("Apps", active: model.mode == .apps)
                tab("Vensters", active: model.mode == .windows)
                Spacer()
                Image(systemName: "magnifyingglass").opacity(0.5)
                Text(model.filter.isEmpty ? "Typ om te filteren" : model.filter)
                    .opacity(model.filter.isEmpty ? 0.4 : 1)
                    .frame(minWidth: 140, alignment: .leading)
                Text("\(items.count)").font(.system(size: 11, design: .monospaced)).opacity(0.5)
            }
            .padding(10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            RowView(item: item, selected: index == model.selection)
                                .id(item.id)
                                .onTapGesture { model.selection = index }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { newValue in
                    let v = model.visible
                    if v.indices.contains(newValue) { proxy.scrollTo(v[newValue].id) }
                }
            }
            .overlay {
                if model.needsPermission {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.shield").font(.system(size: 34)).opacity(0.7)
                        Text("Sluiter heeft toegang nodig om vensters te zien en te sluiten")
                            .font(.system(size: 14, weight: .semibold))
                        Text("1. Druk op ⏎ — Systeeminstellingen opent\n2. Zet ‘Sluiter’ aan bij Toegankelijkheid\n3. Kom terug: de lijst laadt vanzelf")
                            .font(.system(size: 12)).opacity(0.75).multilineTextAlignment(.leading)
                        Button("Open Instellingen  ⏎") { model.requestPermission() }
                    }
                    .padding(24)
                } else if items.isEmpty {
                    Text(model.loading ? "Laden…" : "Niets meer open 🎉").opacity(0.5)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("↑↓ kiezen · spatie/⏎ sluiten · ⇧⏎ forceer stop · ⌘⏎ alles · ⇥ apps/vensters · ⌘R ververs · esc")
                    .font(.system(size: 11)).opacity(0.6)
                if !model.status.isEmpty {
                    Text(model.status).font(.system(size: 11, weight: .medium)).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }

    private func tab(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : Color.clear))
    }
}

