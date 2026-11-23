import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Darwin

// MARK: - Weergave

struct RowView: View {
    let item: Item
    let selected: Bool
    let isProtected: Bool
    var isMarked = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(selected ? .white : (isMarked ? .accentColor : .secondary))
                .opacity(isMarked || selected ? 1 : 0.25)
            if let icon = item.icon {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            } else {
                Color.clear.frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if item.notResponding {
                    Text("reageert niet — ⇧⏎ om geforceerd te stoppen")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selected ? .white : .red)
                        .lineLimit(1)
                } else if !subtitleText.isEmpty {
                    Text(subtitleText).font(.system(size: 11)).opacity(0.65).lineLimit(1)
                }
            }
            Spacer()
            if isProtected {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundColor(selected ? .white : .orange)
                    .help("Beschermd: wordt niet meegesloten")
            }
            if item.kind == .app {
                Text(cpuText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(selected ? .white : cpuColor)
                    .frame(width: 52, alignment: .trailing)
                    .help("CPU-gebruik")
                Text(memoryText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(selected ? .white : memoryColor)
                    .frame(width: 66, alignment: .trailing)
                    .help("Geheugengebruik (incl. hulpprocessen)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundColor(selected ? .white : .primary)
        .background(RoundedRectangle(cornerRadius: 7).fill(
            selected ? Color.accentColor
                     : isMarked ? Color.accentColor.opacity(0.18)
                     : item.notResponding ? Color.red.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
    }

    private var memoryText: String {
        item.memoryMB >= 1024 ? String(format: "%.1f GB", item.memoryMB / 1024)
                              : String(format: "%.0f MB", item.memoryMB)
    }

    private var subtitleText: String {
        guard item.kind == .app else { return item.subtitle }
        let usage = UsageTracker.shared.describe(item.lastUsed)
        return item.subtitle.isEmpty ? usage : "\(item.subtitle) · \(usage)"
    }

    private var cpuText: String {
        guard let cpu = item.cpuPercent else { return "—" }
        return cpu < 10 ? String(format: "%.1f%%", cpu) : String(format: "%.0f%%", cpu)
    }

    private var cpuColor: Color {
        guard let cpu = item.cpuPercent else { return .secondary }
        return cpu > 80 ? .red : cpu > 30 ? .orange : .secondary
    }

    private var memoryColor: Color {
        item.memoryMB > 2048 ? .red : item.memoryMB > 800 ? .orange : .secondary
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let items = model.visible
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Model.Mode.allCases, id: \.self) { m in
                    tab(m.title, active: model.mode == m)
                        .onTapGesture { model.setMode(m) }
                }
                Spacer()
                if model.mode == .apps {
                    Menu {
                        ForEach(Model.SortOrder.allCases, id: \.self) { order in
                            Button {
                                model.sortOrder = order
                            } label: {
                                if order == model.sortOrder { Label(order.rawValue, systemImage: "checkmark") }
                                else { Text(order.rawValue) }
                            }
                        }
                    } label: {
                        Label(model.sortOrder.rawValue, systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Sorteren (⌘S wisselt)")
                }
                Image(systemName: "magnifyingglass").opacity(0.5)
                Text(model.filter.isEmpty ? "Typ om te filteren" : model.filter)
                    .opacity(model.filter.isEmpty ? 0.4 : 1)
                    .frame(minWidth: 140, alignment: .leading)
                if !model.marked.isEmpty {
                    Text("\(model.marked.count) gemarkeerd")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                }
                Text("\(items.count)").font(.system(size: 11, design: .monospaced)).opacity(0.5)
            }
            .padding(10)

            if let stats = model.stats {
                StatsBar(stats: stats)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if let key = model.groupKey(item), index == 0 || model.groupKey(items[index - 1]) != key {
                                HStack(spacing: 6) {
                                    if let icon = item.icon {
                                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                                    }
                                    Text(model.groupTitle(for: item, in: items))
                                        .font(.system(size: 11, weight: .semibold))
                                        .opacity(0.6)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 2 : 10)
                                .padding(.bottom, 2)
                            }
                            RowView(item: item, selected: index == model.selection,
                                    isProtected: settings.isProtected(item.bundleID),
                                    isMarked: model.marked.contains(item.id))
                                .id(item.id)
                                .onTapGesture(count: 2) {
                                    model.selection = index
                                    model.focusSelected()
                                }
                                .onTapGesture {
                                    if NSEvent.modifierFlags.contains(.command) { model.toggleMark(at: index) }
                                    else { model.selection = index }
                                }
                                .contextMenu {
                                    Button("Toon (→)") { model.selection = index; model.focusSelected() }
                                    Button("Sluiten") { model.selection = index; model.closeSelected(force: false) }
                                    if item.kind == .app {
                                        Button("Geforceerd stoppen") { model.selection = index; model.closeSelected(force: true) }
                                    }
                                    Button(model.marked.contains(item.id) ? "Markering weghalen" : "Markeren") {
                                        model.toggleMark(at: index)
                                    }
                                    Divider()
                                    Button(settings.isProtected(item.bundleID) ? "Bescherming opheffen" : "Beschermen 📌") {
                                        model.selection = index; model.toggleProtectSelected()
                                    }
                                }
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
                    Text(model.loading ? "Laden…"
                         : model.mode == .tabs ? "Geen tabbladen gevonden.\nOndersteund: Chrome, Brave, Edge, Vivaldi, Chromium en Safari."
                         : "Niets meer open 🎉")
                        .multilineTextAlignment(.center)
                        .opacity(0.5)
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("↑↓ kiezen · spatie/⏎ sluiten · ⇧↑↓/⌘A markeren · ⇧⏎ forceer · ⌘⏎ alles · → toon · ⌘P beschermen · ⌘⌫ opruimen · ⇥ wissel")
                        .font(.system(size: 11)).opacity(0.6)
                    if !model.status.isEmpty {
                        Text(model.status).font(.system(size: 11, weight: .medium)).lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    model.cleanUp()
                } label: {
                    Label("Opruimen", systemImage: "sparkles")
                }
                .help("Sluit alle apps behalve beschermde (⌘⌫)")
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


// MARK: - Systeembalk

struct StatsBar: View {
    let stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "memorychip").opacity(0.6)
                    ProgressView(value: stats.memoryFraction)
                        .progressViewStyle(.linear)
                        .tint(pressureColor)
                        .frame(width: 90)
                    Text(String(format: "%.1f / %.0f GB", stats.memoryUsedGB, stats.memoryTotalGB))
                        .font(.system(size: 11, design: .monospaced))
                }
                .help("Gebruikt geheugen (zoals Activiteitenweergave)")

                Label(pressureText, systemImage: "gauge.medium")
                    .foregroundColor(pressureColor)
                    .help("Geheugendruk: hoe hard macOS moet werken om alles in het geheugen te houden")

                Label(stats.cpuPercent.map { String(format: "CPU %.0f%%", $0) } ?? "CPU —", systemImage: "cpu")
                    .foregroundColor((stats.cpuPercent ?? 0) > 80 ? .red : (stats.cpuPercent ?? 0) > 50 ? .orange : .primary)

                if stats.swapUsedGB >= 0.1 {
                    Label(String(format: "Swap %.1f GB", stats.swapUsedGB), systemImage: "arrow.left.arrow.right")
                        .foregroundColor(stats.swapUsedGB > 4 ? .orange : .secondary)
                        .help("Swap: geheugen dat naar de schijf is uitgeweken. Veel swap = trage Mac.")
                }
                Spacer()
            }
            .font(.system(size: 11))
            .labelStyle(.titleAndIcon)

            if let advice {
                Text(advice)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(pressureColor == .primary ? .orange : pressureColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var pressureText: String {
        switch stats.pressure {
        case .normal: return "Druk: normaal"
        case .warning: return "Druk: hoog"
        case .critical: return "Druk: kritiek"
        }
    }

    private var pressureColor: Color {
        switch stats.pressure {
        case .normal: return stats.memoryFraction > 0.9 ? .orange : .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var advice: String? {
        switch stats.pressure {
        case .critical: return "⚠️ Je Mac heeft ernstig geheugentekort — sluit de bovenste apps in de lijst."
        case .warning: return "Je Mac krijgt geheugentekort — sluit een paar grote apps om hem sneller te maken."
        case .normal:
            if let cpu = stats.cpuPercent, cpu > 85 { return "De processor draait vol — kijk welke app veel CPU gebruikt." }
            return nil
        }
    }
}
