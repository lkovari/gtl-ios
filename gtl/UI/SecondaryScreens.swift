import SwiftUI
import UIKit

struct SettingsScreen: View {
    @Bindable var model: TrackerModel
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                usageCard
                section(L10n.text("Appearance", "Megjelenés"), id: "appearance") {
                    toggle(L10n.text("Use downloaded map", "Letöltött térkép"), \.useOfflineMap)
                    toggle(L10n.text("Simplify track on map", "Útvonal egyszerűsítése"), \.optimizationActive)
                    toggle(L10n.text("Show last logged route", "Utolsó útvonal"), \.showLastTrackOnMap)
                    toggle(L10n.text("Keep whole track", "Teljes útvonal"), \.keepWholeTrackOnScreen)
                    toggle(L10n.text("Speed scale always open", "Sebességskála mindig nyitva"), \.speedLegendAlwaysOpen)
                    toggle(L10n.text("Show accuracy marker", "Pontosság jelölő"), \.showAccuracyMarker)
                    toggle(L10n.text("Show fix cloud", "Pozíciófelhő"), \.showFixCloud)
                }
                section(L10n.text("Theme", "Téma"), id: "theme") {
                    toggle(L10n.text("Auto theme change", "Automatikus témaváltás"), \.autoTheme)
                        .accessibilityIdentifier("settings.autoTheme")
                    if model.settings.autoTheme {
                        Text(themeCaption)
                            .font(.footnote)
                            .opacity(0.7)
                            .accessibilityIdentifier("settings.themeCaption")
                    } else {
                        Picker(L10n.text("Theme", "Téma"), selection: Binding(
                            get: { model.settings.manualTheme },
                            set: { value in model.updateSettings { $0.manualTheme = value } }
                        )) {
                            Text(L10n.text("Light", "Világos")).tag(ThemeChoice.light)
                            Text(L10n.text("Dark", "Sötét")).tag(ThemeChoice.dark)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.manualTheme")
                    }
                }
                if model.settings.useOfflineMap {
                    section(OfflineLayerToggles.title(model.settings), id: "offline") {
                        OfflineLayerToggles(model: model)
                    }
                }
                section(L10n.text("Recording", "Rögzítés"), id: "recording") {
                    toggle(L10n.text("Keep screen on while logging", "Képernyő bekapcsolva naplózás közben"), \.keepScreenOnWhileLogging)
                    toggle(L10n.text("Smooth recorded track", "Simított nyomvonal"), \.trackSmoothingEnabled)
                    toggle(L10n.text("Hold still when stopped", "Megálláskor tartás"), \.stationaryLockEnabled)
                    VStack(alignment: .leading) {
                        Text(L10n.text("Recording density", "Rögzítési sűrűség"))
                        Slider(value: Binding(
                            get: { Double(model.settings.recordingDensityValue) },
                            set: { value in model.updateSettings { $0.recordingDensityValue = Float(value) } }
                        ), in: 0...1)
                    }
                    Text(L10n.text(
                        "Keep screen on only stops the display from dimming. After Start, a locked screen or another app does not stop the recording, and the blue indicator stays until Stop. Force quitting the app stops it.",
                        "A Képernyő bekapcsolva csak az automatikus elsötétítést akadályozza. Az Indítás után a zárolás vagy egy másik app nem állítja meg a rögzítést, és a kék jelző a Leállításig látszik. Az app kényszerített bezárása leállítja."
                    ))
                    .font(.footnote)
                    .opacity(0.7)
                }
                if model.altimeterAvailable {
                    section(L10n.text("Barometer", "Barométer"), id: "barometer") {
                        toggle(L10n.text("Auto-calibrate", "Automatikus kalibrálás"), \.autoCalibrateBaroEnabled)
                        VStack(alignment: .leading) {
                            Text("QNH \(String(format: "%.1f", model.settings.qnhHpa)) hPa")
                            Slider(value: Binding(
                                get: { Double(model.settings.qnhHpa) },
                                set: { value in model.updateSettings { $0.qnhHpa = Float(value) } }
                            ), in: Double(BaroAltitude.minQnhHpa)...Double(BaroAltitude.maxQnhHpa))
                        }
                        HStack(spacing: 12) {
                            Button(L10n.text("Calibrate", "Kalibrálás")) {
                                if let pressure = model.pressureHpa, let gps = model.altitude {
                                    model.updateSettings { $0.baroPressureOffsetHpa = BaroAltitude.offsetHpa(pressureHpa: pressure, gpsMeters: gps, qnhHpa: $0.qnhHpa) }
                                }
                            }
                            Button(L10n.text("Reset", "Visszaállítás")) {
                                model.updateSettings { $0.baroPressureOffsetHpa = 0 }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                section(L10n.text("Privacy policy", "Adatvédelmi nyilatkozat"), id: "privacy") {
                    Link(L10n.text("Privacy policy", "Adatvédelmi nyilatkozat"), destination: AppLinks.privacyPolicy)
                        .foregroundStyle(GtlColor.titleMagenta)
                }
            }
            .padding(16)
        }
        .background { GtlBackground() }
        .navigationTitle(L10n.text("Settings", "Beállítások"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Usage type", "Használati mód"))
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                ForEach(UsageType.selectable, id: \.self) { usage in
                    let selected = model.settings.usageType == usage
                    Button {
                        model.setUsage(usage)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon(usage))
                                .font(.title3)
                                .frame(height: 24)
                            Text(label(usage))
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? AnyShapeStyle(GtlColor.titleMagenta) : AnyShapeStyle(.primary))
                    .accessibilityIdentifier("settings.usage.\(usage.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                Text(L10n.text("Units", "Mértékegység"))
                    .font(.headline)
                unitChip(L10n.text("Metric", "Metrikus"), id: "Metric", .METRIC)
                unitChip(L10n.text("Imperial", "Angolszász"), id: "Imperial", .IMPERIAL)
                unitChip("ICAO", id: "ICAO", .ICAO)
            }
        }
        .cardSurface()
    }

    private func unitChip(_ title: String, id: String, _ system: MeasurementSystem) -> some View {
        let selected = model.settings.measurementSystem == system
        return Button {
            model.updateSettings { $0.measurementSystem = system }
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(selected ? GtlColor.titleMagenta.opacity(0.22) : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? GtlColor.titleMagenta : Color.secondary.opacity(0.5)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.units.\(id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func icon(_ usage: UsageType) -> String {
        switch usage {
        case .AIRCRAFT: return "airplane"
        case .WATERCRAFT: return "ferry.fill"
        case .FOUR_WHEELERS: return "car.fill"
        case .TWO_WHEELERS: return "motorcycle.fill"
        case .BICYCLE: return "bicycle"
        case .RUNNER: return "figure.run"
        default: return "location.fill"
        }
    }

    private func section<Content: View>(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        AccordionCard(title: title, expanded: expanded.contains(id)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
    }

    private func toggle(_ title: String, _ key: WritableKeyPath<GtlSettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.settings[keyPath: key] },
            set: { value in model.updateSettings { $0[keyPath: key] = value } }
        ))
    }

    private func label(_ usage: UsageType) -> String { usageLabel(usage) }

    private var themeCaption: String {
        let now = Date()
        guard let coordinate = model.themeCoordinate, let twilight = model.civilTwilight(on: now) else {
            return L10n.text(
                "Your location is not known yet. Until it is, the theme follows the iPhone setting.",
                "A helyzeted még nem ismert. Addig a téma az iPhone beállítását követi."
            )
        }
        guard let dawn = twilight.dawn, let dusk = twilight.dusk else {
            let daylight = SolarDaylight.isDaylight(date: now, latitude: coordinate.latitude, longitude: coordinate.longitude)
            return daylight
                ? L10n.text("Here the sun stays above the twilight line all day, so the theme stays light.", "Itt a nap egész nap a szürkületi határ fölött van, ezért a téma világos marad.")
                : L10n.text("Here the sun stays below the twilight line all day, so the theme stays dark.", "Itt a nap egész nap a szürkületi határ alatt van, ezért a téma sötét marad.")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return L10n.text(
            "Light from dawn to dusk at your location, dark outside it. Today: \(formatter.string(from: dawn)) – \(formatter.string(from: dusk)).",
            "A helyzeted szerinti pirkadattól alkonyatig világos, azon kívül sötét. Ma: \(formatter.string(from: dawn)) – \(formatter.string(from: dusk))."
        )
    }
}

struct MapDownloadScreen: View {
    @Bindable var model: TrackerModel
    var body: some View {
        List {
            if let error = model.downloadError {
                Text(error).foregroundStyle(GtlColor.carmine)
            }
            Section("Turistautak.hu") {
                row(id: OsmCatalog.tuhuId, title: "Turistautak.hu", country: "HU") { model.downloadTuhu() }
            }
            ForEach(OsmCatalog.groups()) { group in
                Section(group.title) {
                    ForEach(group.regions) { region in
                        row(id: region.id, title: OsmCatalog.localizedTitle(region), country: region.countryCode) { model.download(region) }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("Offline maps", "Offline térképek"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadCatalogSizes() }
        .alert(
            L10n.text("Download on mobile data?", "Letöltés mobilhálózaton?"),
            isPresented: Binding(
                get: { model.pendingCellularDownload != nil },
                set: { _ in }
            )
        ) {
            Button(L10n.text("Download", "Letöltés")) { model.confirmCellularDownload() }
            Button(L10n.text("Cancel", "Mégsem"), role: .cancel) { model.cancelCellularDownload() }
        } message: {
            if let pending = model.pendingCellularDownload {
                Text(L10n.text(
                    "\(pending.title) is \(ByteCountFormatter.string(fromByteCount: pending.bytes, countStyle: .file)). This download uses mobile data.",
                    "\(pending.title) mérete \(ByteCountFormatter.string(fromByteCount: pending.bytes, countStyle: .file)). A letöltés mobiladatot használ."
                ))
            }
        }
    }

    private func row(id: String, title: String, country: String, download: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if let fraction = model.downloadFraction[id], fraction < 1 {
                ProgressView(value: fraction)
            }
            HStack {
                if model.downloadedIds.contains(id) {
                    Button(model.settings.selectedMapId == id && model.settings.useOfflineMap ? L10n.text("In use", "Használatban") : L10n.text("Use", "Használat")) {
                        model.useMap(id)
                    }
                    Button(L10n.text("Delete", "Törlés"), role: .destructive) { model.deleteMap(id) }
                } else {
                    Button(L10n.text("Download", "Letöltés"), action: download)
                }
            }
            .buttonStyle(.bordered)
            Text(caption(id: id, country: country)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func caption(id: String, country: String) -> String {
        guard let bytes = model.catalogSizes[id] else { return country }
        return "\(country) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}

private func usageLabel(_ usage: UsageType) -> String {
    switch usage {
    case .AIRCRAFT: return L10n.text("Aircraft", "Légijármű")
    case .WATERCRAFT: return L10n.text("Watercraft", "Vízi jármű")
    case .FOUR_WHEELERS: return L10n.text("Car", "Autó")
    case .TWO_WHEELERS: return L10n.text("Motorbike", "Motor")
    case .BICYCLE: return L10n.text("Bicycle", "Kerékpár")
    case .RUNNER: return L10n.text("Run/Hike", "Futás/Túra")
    default: return usage.kmlLabel()
    }
}

private struct GpsEventsPage: Hashable {
    var sessionId: Int64
    var text: String
}

struct TracksScreen: View {
    @Bindable var model: TrackerModel
    @State private var selected: Set<Int64> = []
    @State private var sharing = false
    @State private var dumpPage: GpsEventsPage?
    var body: some View {
        List {
            ForEach(model.sessions) { session in
                TrackCard(
                    session: session,
                    preview: model.trackPreviews[session.id],
                    system: model.settings.measurementSystem,
                    selected: selected.contains(session.id)
                )
                .contentShape(Rectangle())
                .onTapGesture { toggle(session.id) }
                .task(id: session.stoppedAt) { await model.loadPreview(for: session) }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { GtlBackground() }
        .navigationTitle(L10n.text("Saved tracks", "Mentett útvonalak"))
        .navigationDestination(item: $dumpPage) { page in
            GpsEventsScreen(text: page.text)
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(L10n.text("Show on map", "Térképen")) {
                    if let id = selected.first { model.showSession(id) }
                }
                .disabled(selected.count != 1)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(L10n.text("Recorded points", "Rögzített pontok")) { openRecordedPoints() }
                    .disabled(selected.count != 1)
                    .accessibilityIdentifier("recordedPoints")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("GPX") { model.share(ids: Array(selected), kmz: false) }.disabled(selected.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button("KMZ") { model.share(ids: Array(selected), kmz: true) }.disabled(selected.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(L10n.text("Delete", "Törlés"), role: .destructive) { model.deleteSessions(selected); selected.removeAll() }
                    .disabled(selected.isEmpty)
            }
        }
        .alert(
            model.exportFailed ? L10n.text("Export failed", "Az exportálás nem sikerült") : L10n.text("Track saved", "Útvonal mentve"),
            isPresented: Binding(get: { model.exportNotice != nil }, set: { if !$0 { model.exportNotice = nil } })
        ) {
            if model.pendingShare != nil && !model.exportFailed {
                Button(L10n.text("Share", "Megosztás")) { sharing = true }
            }
            Button(L10n.text("OK", "Rendben"), role: .cancel) {}
        } message: {
            Text(model.exportNotice ?? "")
        }
        .sheet(isPresented: $sharing) {
            if let url = model.pendingShare { ShareSheet(url: url) }
        }
    }

    private func toggle(_ id: Int64) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func openRecordedPoints() {
        guard selected.count == 1, let id = selected.first, let session = model.sessions.first(where: { $0.id == id }) else { return }
        Task {
            let text = await model.gpsEventsDump(for: session)
            dumpPage = GpsEventsPage(sessionId: session.id, text: text)
        }
    }

}

private struct TrackCard: View {
    var session: TrackSession
    var preview: TrackPreview?
    var system: MeasurementSystem
    var selected: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            TrackThumbnailView(outline: preview?.outline)
                .frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("savedTrackDate.\(session.id)")
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                statsLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? GtlColor.hudTeal : Color.secondary.opacity(0.5))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(scheme == .dark ? GtlColor.cockpitPanel : Color.white)
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 6, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? GtlColor.hudTeal : Color.primary.opacity(0.06), lineWidth: selected ? 2 : 1)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var title: String {
        Self.titleFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.startedAt) / 1000))
    }

    private var subtitle: String {
        let usage = UsageType(rawValue: session.usageType).map(usageLabel) ?? session.usageType
        guard let stats = preview?.stats, stats.pointCount > 1 else { return usage }
        return "\(usage) · \(Units.formatDistance(stats.odometerMeters, system))"
    }

    @ViewBuilder private var statsLine: some View {
        if let stats = preview?.stats {
            HStack(spacing: 8) {
                Text(duration(stats.elapsedMillis))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                Text("\(L10n.text("Avg", "Átl")):\(speed(stats.averageSpeedMps))")
                Text("Max:\(speed(stats.maxSpeedMps))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text(" ").font(.caption)
        }
    }

    private func speed(_ metersPerSecond: Float) -> String {
        Units.hudSpeedNumber(metersPerSecond, system) + Units.hudSpeedUnit(system)
    }

    private func duration(_ millis: Int64) -> String {
        let seconds = max(0, millis / 1000)
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

private struct TrackThumbnailView: View {
    var outline: [TrackThumbnailPoint]?

    var body: some View {
        Canvas { context, size in
            guard let outline, !outline.isEmpty else { return }
            let inset: CGFloat = 9
            let side = min(size.width, size.height) - inset * 2
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let points = outline.map { CGPoint(x: origin.x + $0.x * side, y: origin.y + $0.y * side) }
            var path = Path()
            path.addLines(points)
            let stroke = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(GtlColor.routeMagenta.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(GtlColor.routeMagenta), style: stroke)
            if let first = points.first, let last = points.last {
                dot(context, at: last, color: GtlColor.moonCream)
                dot(context, at: first, color: GtlColor.hudCyan)
            }
        }
        .background(
            LinearGradient(colors: [GtlColor.cockpitPanel, GtlColor.cockpit], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GtlColor.hudCyan.opacity(0.25), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func dot(_ context: GraphicsContext, at point: CGPoint, color: Color) {
        let rect = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

private struct GpsEventsBlockHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct GpsEventsScreen: View {
    var text: String
    @State private var copied = false
    @State private var copyToken = 0
    @State private var cachedWidths: [CGFloat] = []
    @State private var sessionHeight: CGFloat = 108
    @State private var headerHeight: CGFloat = 36

    var body: some View {
        let grid = GpsEventsDump.grid(from: text)
        let widths = cachedWidths.count == grid.columns.count ? cachedWidths : GpsEventsDump.columnWidths(columns: grid.columns, rows: grid.rows)
        let tableWidth = widths.reduce(0, +)
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                sessionBlock(grid.sessionLines)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeader(grid.columns, widths: widths)
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(grid.rows.indices, id: \.self) { index in
                                    dataRow(grid.rows[index], widths: widths, stripe: index.isMultiple(of: 2))
                                }
                            }
                            .frame(width: tableWidth, alignment: .leading)
                        }
                        .frame(width: max(tableWidth, 1), height: rowHeight(in: geo.size.height))
                    }
                }
                .frame(height: max(geo.size.height - sessionHeight, 0))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(L10n.text("Recorded points", "Rögzített pontok"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: copyAll) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("gpsEventsCopy")
                .accessibilityLabel(L10n.text("Copy", "Másolás"))
            }
        }
        .onAppear {
            if cachedWidths.count != grid.columns.count {
                cachedWidths = GpsEventsDump.columnWidths(columns: grid.columns, rows: grid.rows)
            }
        }
        .onPreferenceChange(GpsEventsBlockHeight.self) { sessionHeight = $0 }
    }

    private func rowHeight(in total: CGFloat) -> CGFloat {
        max(total - sessionHeight - headerHeight, 0)
    }

    private func sessionBlock(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(parts.first ?? "")
                        .foregroundStyle(.secondary)
                    Text(parts.count > 1 ? parts[1] : "")
                }
                .font(.system(size: GpsEventsDump.cellFontSize, design: .monospaced))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: GpsEventsBlockHeight.self, value: geo.size.height)
            }
        }
        .accessibilityIdentifier("gpsEventsDump")
    }

    private func columnHeader(_ columns: [String], widths: [CGFloat]) -> some View {
        columnLine(columns, widths: widths, header: true)
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(alignment: .bottom) { Divider() }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: HeaderHeightKey.self, value: geo.size.height)
                }
            }
            .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
            .accessibilityIdentifier("gpsEventsHeader")
    }

    private func dataRow(_ cells: [String], widths: [CGFloat], stripe: Bool) -> some View {
        columnLine(cells, widths: widths, header: false)
            .background(stripe ? Color.primary.opacity(0.05) : Color.clear)
    }

    private func columnLine(_ cells: [String], widths: [CGFloat], header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(widths.indices, id: \.self) { index in
                Text(index < cells.count ? cells[index] : "")
                    .font(.system(size: GpsEventsDump.cellFontSize, weight: header ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(width: widths[index], alignment: .leading)
                    .padding(.vertical, header ? 8 : 4)
            }
        }
    }

    private func copyAll() {
        UIPasteboard.general.string = text
        copied = true
        copyToken += 1
        let token = copyToken
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copyToken == token { copied = false }
        }
    }
}

private struct HeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 36
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct HelpScreen: View {
    var model: TrackerModel
    @State private var expanded = "usage"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                section(L10n.text("Usage", "Használati mód"), id: "usage") {
                    Text(L10n.text(
                        "Allow location when asked. GPS and Compass update while this screen is open. Tap Start to record a route into the database on this phone, draw it on the Map, and fill the Route totals. Tap Stop to end the session. A locked screen or the app in the background keeps recording until Stop. Menu → Saved tracks to delete a route, show it on the map, or share KMZ or GPX. Settings picks usage (motorbike is the default), units, and whether the last track stays on the map. Menu → Download offline map for OSM regions or Turistautak (Hungary). The logged track is not uploaded to our server, and nothing stored on the phone is shared with a third party. The map, search, a route, and an address send Apple the coordinate needed for that request.",
                        "A helyhozzáférést az első kérdésnél engedélyezd. A GPS és az iránytű a képernyőn él. Az Indítás a telefon adatbázisába rögzíti az útvonalat, kirajzolja a Térképen, és kitölti az Útvonal összesítőket. A Leállítás bezárja a munkamenetet. Zárolt képernyőn és háttérben a rögzítés a Leállításig folytatódik. Menü → Mentett útvonalak: törlés, megjelenítés, vagy KMZ / GPX. A Beállításokban a használat (alapból motor), a mértékegység, és hogy maradjon-e az utolsó track. Menü → Offline térkép: OSM-régió vagy Turistautak (Magyarország). A naplózott track nem kerül a szerverünkre, és a telefonon tárolt adat nem kerül harmadik félhez. A térkép, a keresés, az útvonal és a cím az Apple-nek küldi az ehhez szükséges koordinátát."
                    ))
                }
                section(L10n.text("Settings", "Beállítások"), id: "settings") {
                    Text(L10n.text(
                        "Usage writes a preset for units, smoothing, density, and map simplify. Aircraft and watercraft default to ICAO; the others default to metric. You can change any control afterwards. Keep screen on while logging is under Recording. It only keeps the display awake; recording continues on a locked screen either way. Usage type and Units are always on screen at the top of Settings. Every other group sits under its own heading: tap a heading to open it, and several can stay open at once. Theme holds Auto theme change and, when it is off, Light or Dark. OSM and Turistautak layer switches are on the map layers button, and the same group appears in Settings while Use downloaded map is on. The barometer group appears only if this phone has a pressure sensor. Apple Maps is standard, satellite, or hybrid, each with realistic elevation.",
                        "A használat előbeállítást ír a mértékegységre, a simításra, a sűrűségre és a térképi egyszerűsítésre. Repülőnél és hajónál az alap az ICAO, a többinél a metrikus. Utána bármelyik kapcsoló módosítható. A képernyő bekapcsolva hagyása a Rögzítés alatt van. Csak a kijelzőt tartja ébren; a rögzítés zárolt képernyőn enélkül is folytatódik. A használati mód és a mértékegység a Beállítások tetején mindig látszik. A többi csoport saját címsor alatt van: a címsorra koppintva nyílik le, és egyszerre több is nyitva lehet. A Téma csoportban van az Automatikus témaváltás, és ha ki van kapcsolva, a Világos vagy Sötét választó. Az OSM és a Turistautak rétegek a térkép réteg gombján vannak, és ugyanez a csoport a Beállításokban akkor látszik, ha a Letöltött térkép be van kapcsolva. A barométer csoport csak akkor látszik, ha van nyomásszenzor. Az Apple térkép standard, műhold vagy hibrid, mindegyik valós domborzattal."
                    ))
                }
                section(L10n.text("Theme", "Téma"), id: "theme") {
                    Text(L10n.text(
                        "Settings → Theme. With Auto theme change on, the app and the maps are light between dawn and dusk at your location and dark outside it. Dawn and dusk are civil twilight, when the sun is 6 degrees below the horizon, worked out on the phone from your position and the date, not from a fixed clock time. Near the poles the theme can stay light or dark all day. Until your position is known, the theme follows the iPhone setting. With Auto theme change off, pick Light or Dark. Apple Maps and the downloaded OSM and Turistautak maps follow the theme; on a dark offline map the track gets a light edge so every speed color stays visible.",
                        "Beállítások → Téma. Ha az Automatikus témaváltás be van kapcsolva, az app és a térképek a helyzeted szerinti pirkadat és alkonyat között világosak, azon kívül sötétek. A pirkadat és az alkonyat a polgári szürkület, amikor a nap 6 fokkal a horizont alatt van; ezt a telefon számolja a helyzetedből és a dátumból, nem egy rögzített órából. A sarkok közelében a téma egész nap világos vagy sötét maradhat. Amíg a helyzeted nem ismert, a téma az iPhone beállítását követi. Kikapcsolt Automatikus témaváltásnál Világos vagy Sötét választható. Az Apple térkép és a letöltött OSM- és Turistautak-térkép követi a témát; sötét offline térképen a nyomvonal világos szegélyt kap, hogy minden sebességszín látszódjon."
                    ))
                }
                section(L10n.text("Track logging", "Nyomvonal rögzítés"), id: "logging") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "Start begins recording in the foreground. It needs location allowed While Using the App and Precise Location on. GTL never asks for Always. After Start, locking the screen or switching to another app does not stop the recording, and the blue location indicator stays visible until Stop. Force quitting GTL from the app switcher stops the recording, and it does not restart on its own: open GTL and tap Start again. If location or Precise Location is off, Start shows a message with a button to Settings on every tab. Settings → Recording → Keep screen on while logging only keeps the display from dimming.",
                            "Az Indítás az előtérben kezdi a rögzítést. Ehhez a hely az app használata közben legyen engedélyezve, és a Pontos hely legyen bekapcsolva. A GTL soha nem kér Mindig engedélyt. Az Indítás után a képernyő zárolása vagy egy másik app megnyitása nem állítja meg a rögzítést, és a kék helyjelző a Leállításig látszik. Ha a GTL-t az appváltóban kényszerítve bezárod, a rögzítés leáll, és magától nem indul újra: nyisd meg a GTL-t, és nyomd meg újra az Indítást. Ha a hely vagy a Pontos hely ki van kapcsolva, az Indítás bármelyik fülön üzenetet ad, egy gombbal a Beállításokhoz. Beállítások → Rögzítés → Képernyő bekapcsolva naplózás közben csak az automatikus elsötétítést akadályozza."
                        ))
                        Text(L10n.text(
                            "Kalman smooths stored points when Smooth recorded track is on. Simplify only thins the line drawn on the map. The stored route and shared KMZ or GPX keep every accepted point. Smart density uses speed bands. Run/Hike and bicycle keep points closer together. Recording quality uses horizontal accuracy. Fixes older than 10 seconds are dropped.",
                            "A Kalman a letárolt pontokat simítja, ha a Rögzített útvonal simítása be van. Az egyszerűsítés csak a térképen rajzolt vonalat ritkítja. A tárolt útvonal és a megosztott KMZ vagy GPX minden elfogadott pontot megtart. Az okos sűrűség sebességsávokat használ. Futásnál és kerékpárnál sűrűbbek a pontok. A rögzítés a vízszintes pontosságot használja. A 10 másodpercnél régebbi fixek kiesnek."
                        ))
                    }
                }
                section("GPS", id: "gps") {
                    Text(L10n.text(
                        "Latitude, longitude, horizontal accuracy, vertical accuracy, GPS altitude, ellipsoid altitude, barometric altitude, pressure, and fix age. Barometric altitude and pressure appear while logging when this phone has a pressure sensor. Logging status is on this tab. If location or Precise Location is off, this tab explains it and opens Location settings. There is no ambient temperature sensor, so temperature is not stored.",
                        "Szélesség, hosszúság, vízszintes pontosság, függőleges pontosság, GPS-magasság, ellipszoidi magasság, barometrikus magasság, nyomás és a fix kora. A barometrikus magasság és a nyomás naplózás közben látszik, ha van nyomásszenzor. A naplózás állapota ezen a fülön van. Ha a hely vagy a Pontos hely ki van kapcsolva, ez a fül elmagyarázza, és megnyitja a Helyzet beállításokat. Nincs hőmérséklet-szenzor, ezért a hőmérséklet nem kerül tárolásra."
                    ))
                }
                section(L10n.text("Route", "Útvonal"), id: "route") {
                    Text(L10n.text(
                        "Session totals after Start: elapsed time, odometer, time moving, time waiting, altitude, bearing, speed, and a GPS elevation profile. A dashed line is barometric altitude when pressure samples exist. Speed is 0 while idle.",
                        "Indítás utáni összesítő: eltelt idő, számláló, mozgásban töltött idő, várakozás, magasság, irányszög, sebesség, és GPS magassági profil. A szaggatott vonal a barometrikus magasság, ha van nyomásminta. Idle-ben a sebesség 0."
                    ))
                }
                section(L10n.text("Map", "Térkép"), id: "map") {
                    Text(L10n.text(
                        "The map centers on you when a fix exists. Idle, you can pan away. After Start it follows you, tilts the camera to about 52 degrees, and turns the map and the arrow with your direction of travel. Course is used above 1 m/s; below that the compass is used. Two fingers tilt the camera, and the tilt stays. Tap the north dial to restore 52 degrees and direction-up. Keep whole track on screen stays a flat north-up view. Apple Maps standard, satellite, and hybrid use realistic elevation, with no API key. A downloaded OSM or Turistautak map can tilt and follow heading, but the ground stays flat. The track color runs from blue, slow, to the fastest color for the current usage, including a saved track. The dots are that scale. The list shows each band in the unit from Settings, and Speed scale always open keeps it on screen. Turn that off and the dots remain: a tap shows the bands, and another tap hides them. The HUD speed number uses the color of the current band. Tap the map, then Route, to ask Apple for a walking, cycling, or driving path. Hike and run use walking, bicycle uses cycling, car and motorbike use driving. Aircraft and watercraft ask you to pick walk, bicycle, or car. The request needs a network and sends the two coordinates to Apple. The logged track stays on this phone. Tap the map, then Address, to ask Apple for the nearest street address of that one point. The lookup needs a network, including on an offline map, and sends that coordinate to Apple. The logged track stays on this phone. Tap the route chip to clear the line. Straight-line Distance is separate. The HUD shows large speed, the unit from Settings, and accuracy in metres. While logging it also shows odometer, elapsed time, and REC. It is hidden when a saved track is on the map and you are not logging. Altitude is not on the HUD. While logging, if GPS quality is too low to accept a point, a notice appears under the top buttons. Standing still, the HUD and the Route speed show 0: a speed within its own measurement error, or a move smaller than the position accuracy, counts as standing, and two readings in a row are needed to switch between 0 and moving. The stored track is not changed by this.",
                        "A térkép a fixre centrál, ha van. Idle-ben elhúzható. Indítás után követ, a kamerát kb. 52 fokra dönti, és a térképet meg a nyilat a haladási iránnyal forgatja. 1 m/s felett a course, alatta az iránytű. Két ujjal dönthető, és a dőlés megmarad. Az észak-tárcsa visszaállítja az 52 fokot és a menetirányt. A teljes track a képen felülnézet, észak felé. Az Apple standard, műhold és hibrid valós domborzatot használ, API-kulcs nélkül. A letöltött OSM vagy Turistautak térkép dönthető és menetirányba fordul, a talaj lapos marad. A nyomvonal színe a kéktől, ami lassú, a használat leggyorsabb színéig tart, mentett útvonalon is. A pöttyök ez a skála. A lista kiírja a sávokat a beállított mértékegységben, és a Sebességskála mindig nyitva a képen tartja. Ha ez ki van kapcsolva, a pöttyök maradnak: koppintásra jönnek a sávok, újabb koppintásra eltűnnek. A HUD sebességszáma az aktuális sáv színét kapja. Koppintás, majd Útvonal: az Apple gyalog, kerékpárral vagy autóval útvonalat ad. Túra és futás gyalog, kerékpár kerékpár, autó és motor autó. Repülőnél és hajónál gyalog, kerékpár vagy autó közül választasz. A kéréshez hálózat kell, és a két koordináta az Apple-höz megy. A naplózott track a telefonon marad. Koppintás, majd Cím: az Apple ennek az egy pontnak a legközelebbi címét adja. A lekérdezéshez hálózat kell, offline térképen is, és ez az egy koordináta az Apple-höz megy. A naplózott track a telefonon marad. Az útvonal chipje törli a vonalat. A légvonalas Távolság külön van. A HUD a nagy sebességet, a beállított mértékegységet és a pontosságot mutatja méterben. Naplózáskor az út, az eltelt idő és a REC is látszik. Mentett tracknél, ha nem naplózol, a HUD rejtve van. A HUD nem mutat magasságot. Naplózás közben, ha a GPS minősége túl alacsony egy pont elfogadásához, a felső gombok alatt figyelmeztetés jelenik meg. Álló helyzetben a HUD és az Útvonal sebessége 0: a saját mérési hibáján belüli sebesség vagy a helypontosságnál kisebb elmozdulás állásnak számít, és a 0 és a mozgás közötti váltáshoz két egymást követő mérés kell. A tárolt nyomvonalat ez nem változtatja meg."
                    ))
                }
                section(L10n.text("OSM map options", "OSM térkép opciók"), id: "osm") {
                    Text(L10n.text(
                        "These switches are on the map layers button when a downloaded OSM region is on Map, and in Settings while Use downloaded map is on. Buildings, POI, public transport, cycleways, and parks. Terrain relief stays off unless elevation files sit next to the map. Official downloads do not include hillshade.",
                        "Ezek a kapcsolók a térkép réteg gombján vannak, ha egy OSM-régió van a Térképen, a Beállításokban pedig akkor, ha a Letöltött térkép be van kapcsolva. Épületek, POI, tömegközlekedés, kerékpárutak és parkok. A domborzat kikapcsolva marad, amíg nincsenek magasságfájlok a térkép mellett. A hivatalos letöltésben nincs domborzatárnyékolás."
                    ))
                }
                section(L10n.text("Turistautak options", "Turistautak opciók"), id: "tuhu") {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.downloadedIds.contains(OsmCatalog.tuhuId) {
                            Text(L10n.text("The Turistautak map is on this phone.", "A Turistautak térkép a telefonon van."))
                        }
                        Text(L10n.text(
                            "Hungary only. This is a map from Turistautak.hu, not an OSM country download. Trail blazes, paths, contours, minor contours, hiking POI, protected areas, urban POI, and relief apply only while that map is on Map.",
                            "Csak Magyarország. Ez a Turistautak.hu térképe, nem OSM-országletöltés. A jelzések, utak, szintvonalak, mellékszintvonalak, túra POI, védett területek, városi POI és a domborzat csak akkor érvényes, ha ez a térkép van a Térképen."
                        ))
                        Link(L10n.text("Turistautak.hu website", "Turistautak.hu weboldal"), destination: OsmCatalog.tuhuWebsite)
                            .foregroundStyle(GtlColor.titleMagenta)
                    }
                }
                section(L10n.text("Compass", "Iránytű"), id: "compass") {
                    Text(L10n.text(
                        "MAG is magnetic north. TRUE is geographic north: magnetic heading plus declination from the last GPS fix. Switch them on this tab. TRUE needs a GPS fix; without one the dial stays MAG and shows No GPS. If the compass is inaccurate, the tab asks you to wave the phone in a figure-8 so the sensor can calibrate. Works without Start.",
                        "A MAG a mágneses észak. A TRUE a földrajzi észak: a mágneses irányszög plusz a legutóbbi GPS-fix deklinációja. Ezen a fülön váltható. A TRUE-hoz GPS-fix kell; anélkül a számlap MAG marad, és Nincs GPS látszik. Ha az iránytű pontatlan, a fül arra kér, hogy a kalibráláshoz rajzolj nyolcast a levegőben. Indítás nélkül is működik."
                    ))
                }
                section(L10n.text("Sharing KMZ and GPX", "KMZ és GPX megosztás"), id: "share") {
                    Text(L10n.text(
                        "Saved tracks → select sessions → GPX or KMZ. The file is saved in the Files app under On My iPhone → GPS Track Logger → Exports, and a share sheet can copy it elsewhere. KMZ is KML plus start, pause, and stop icons. When the track has a GPS altitude, the line uses absolute mode and that altitude, so Google Earth lifts it off the ground. Icons stay on the ground. Google Earth treats absolute altitude as height above the ellipsoid, so the line can sit a few tens of metres off the terrain. GPX 1.1 has one track per session, with latitude, longitude, GPS elevation in ele, and UTC time. Several sessions become one file.",
                        "Mentett útvonalak → kijelölés → GPX vagy KMZ. A fájl a Fájlok appban van: A(z) iPhone-omon → GPS Track Logger → Exports, és a megosztó lapról máshova is másolható. A KMZ KML, plusz indulás, szünet és megállás ikon. Ha van GPS-magasság, a vonal absolute módban ezt a magasságot használja, ezért a Google Earth kiemeli a terepből. Az ikonok a talajon maradnak. A Google Earth az absolute magasságot az ellipszoidhoz méri, ezért a vonal néhány tíz méterrel a terep fölött vagy alatt ülhet. A GPX 1.1 munkamenetenként egy track: szélesség, hosszúság, GPS-magasság az ele mezőben, és UTC idő. Több munkamenet egy fájlba kerül."
                    ))
                }
                section(L10n.text("Privacy policy", "Adatvédelmi nyilatkozat"), id: "privacy") {
                    Link(L10n.text("Privacy policy", "Adatvédelmi nyilatkozat"), destination: AppLinks.privacyPolicy)
                        .foregroundStyle(GtlColor.titleMagenta)
                }
                section(L10n.text("A stored trackpoint", "Egy tárolt pont"), id: "point") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "One GPS fix in the database. To see every stored point of a route, open Saved tracks, select one route, and tap Recorded points at the bottom.",
                            "Egy GPS-fix az adatbázisban. Egy útvonal összes tárolt pontjához nyisd meg a Mentett útvonalakat, jelölj ki egy útvonalat, és koppints alul a Rögzített pontok gombra."
                        ))
                        .foregroundStyle(.secondary)
                        TrackpointTable()
                    }
                }
            }
            .padding(16)
        }
        .background { GtlBackground() }
        .navigationTitle(L10n.text("Help", "Súgó"))
    }

    private func section<Content: View>(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        AccordionCard(title: title, expanded: expanded == id) {
            expanded = expanded == id ? "" : id
        } content: {
            content()
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AboutScreen: View {
    @Bindable var model: TrackerModel
    @State private var expanded = "app"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                AccordionCard(title: L10n.text("App info", "Alkalmazás adatai"), expanded: expanded == "app") {
                    expanded = expanded == "app" ? "" : "app"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1")  ·  com.lkovari.mobile.apps.gtl")
                        Text("\(L10n.text("Device", "Készülék")): \(UIDevice.current.model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                        Button(L10n.text("Error log", "Hibanapló")) { model.showErrorLog = true }
                            .foregroundStyle(GtlColor.titleMagenta)
                            .accessibilityIdentifier("openErrorLog")
                    }
                }
                AccordionCard(title: L10n.text("Local GPS track logger", "Helyi GPS útvonalnapló"), expanded: expanded == "logger") {
                    expanded = expanded == "logger" ? "" : "logger"
                } content: {
                    Text(L10n.text(
                        "No account, no ads, no IMEI, no remote tracking.",
                        "Nincs fiók, reklám, IMEI vagy távoli követés."
                    ))
                }
                AccordionCard(title: "OSM. OpenStreetMap", expanded: expanded == "osm") {
                    expanded = expanded == "osm" ? "" : "osm"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "The Map tab can show OpenStreetMap data from a file you download on the phone. Map data © OpenStreetMap contributors, licensed under the Open Database License (ODbL).",
                            "A Térkép fül OpenStreetMap adatot mutathat egy telefonra letöltött fájlból. Térképadat © OpenStreetMap közreműködők, Open Database License (ODbL) alatt."
                        ))
                        aboutLink(L10n.text("OpenStreetMap website", "OpenStreetMap weboldal"), "https://www.openstreetmap.org")
                        aboutLink(L10n.text("OpenStreetMap copyright", "OpenStreetMap szerzői jog"), "https://www.openstreetmap.org/copyright")
                    }
                }
                AccordionCard(title: "TUHU. Turistautak.hu", expanded: expanded == "tuhu") {
                    expanded = expanded == "tuhu" ? "" : "tuhu"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "After you download the Turistautak map, Map can show Hungarian hiking waymarks and contours. Map data © Turistautak.hu. Their terms require a clear reference to the site wherever the data is shown. The file is saved on this phone for your own use.",
                            "A Turistautak térkép letöltése után a Térkép magyar turistajelzéseket és szintvonalat tud mutatni. Térképadat © Turistautak.hu. A feltételek egyértelmű hivatkozást kérnek a lapra, ahol az adat látszik. A fájl a saját használatodra kerül a telefonra."
                        ))
                        aboutLink(L10n.text("Turistautak.hu website", "Turistautak.hu weboldal"), "https://turistautak.hu")
                        Link(L10n.text("Turistautak.hu terms", "Turistautak.hu feltételek"), destination: AppLinks.turistautakTerms)
                            .foregroundStyle(GtlColor.titleMagenta)
                    }
                }
                AccordionCard(title: "MapLibre", expanded: expanded == "maplibre") {
                    expanded = expanded == "maplibre" ? "" : "maplibre"
                } content: {
                    Text(L10n.text(
                        "Offline maps are drawn with MapLibre Native, BSD 2-Clause License. Copyright (c) 2021 MapLibre contributors. Copyright (c) 2018-2021 MapTiler.com. Copyright (c) 2014-2020 Mapbox.",
                        "Az offline térképet a MapLibre Native rajzolja, BSD 2-Clause licenc. Copyright (c) 2021 MapLibre contributors. Copyright (c) 2018-2021 MapTiler.com. Copyright (c) 2014-2020 Mapbox."
                    ))
                }
                AccordionCard(title: L10n.text("Support", "Támogatás"), expanded: expanded == "support") {
                    expanded = expanded == "support" ? "" : "support"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Link(L10n.text("Privacy policy", "Adatvédelmi nyilatkozat"), destination: AppLinks.privacyPolicy)
                            .foregroundStyle(GtlColor.titleMagenta)
                        Link("laszlo.kovary@gmail.com", destination: AppLinks.supportMail)
                            .foregroundStyle(GtlColor.titleMagenta)
                    }
                }
                AccordionCard(title: L10n.text("Original repository", "Eredeti tároló"), expanded: expanded == "repo") {
                    expanded = expanded == "repo" ? "" : "repo"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("(before the AI. era)", "(az AI. korszak előtt)"))
                        aboutLink("https://bitbucket.org/laszlokovary/gtl-e/src/master/", "https://bitbucket.org/laszlokovary/gtl-e/src/master/")
                    }
                }
                AccordionCard(title: L10n.text("Copyright", "Szerzői jog"), expanded: expanded == "copyright") {
                    expanded = expanded == "copyright" ? "" : "copyright"
                } content: {
                    Text("Copyright © 2026 by László Kővári")
                        .accessibilityIdentifier("about.author")
                }
            }
            .padding(16)
        }
        .background { GtlBackground() }
        .navigationTitle(L10n.text("About", "Névjegy"))
    }

    private func aboutLink(_ label: String, _ url: String) -> some View {
        Link(label, destination: URL(string: url)!)
            .foregroundStyle(GtlColor.titleMagenta)
    }
}

private struct TrackpointTable: View {
    private var rows: [(String, String)] {
        [
            ("id", L10n.text("primary key", "elsődleges kulcs")),
            ("sessionId", L10n.text("which track", "melyik útvonal")),
            ("timestamp", L10n.text("time (epoch ms)", "idő (epoch ms)")),
            ("latitude / longitude / altitude", L10n.text("location", "hely")),
            ("speed", "m/s"),
            ("bearing", L10n.text("heading °", "irányszög °")),
            ("accuracy", L10n.text("GPS accuracy m", "GPS pontosság m")),
            ("baroAltitude", L10n.text("metres from the barometer when this phone has a pressure sensor", "méter a barométerből, ha van nyomásszenzor")),
            ("pressureHpa", L10n.text("raw hPa, or empty", "nyers hPa, vagy üres")),
            ("accelX / accelY / accelZ", L10n.text("acceleration", "gyorsulás")),
            ("leanAngle", L10n.text("lean °", "dőlés °")),
            ("usageType", L10n.text("usage at this fix", "használat ennél a fixnél")),
            ("isPlacemark", L10n.text("true = START / PAUSE / STOP icon in the KMZ", "igaz = START / PAUSE / STOP ikon a KMZ-ben")),
            ("eventKind", "START, MOVE, PAUSE, STOP")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().opacity(0.35)
                }
                HStack(alignment: .top, spacing: 12) {
                    Text(row.0)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(GtlColor.hudCyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.horizontal, 10)
        .background(GtlColor.cockpitPanel)
        .foregroundStyle(GtlColor.moonCream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AccordionCard<Content: View>: View {
    var title: String
    var expanded: Bool
    var onToggle: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                content()
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
    }
}

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? GtlColor.cockpitPanel : Color.white.opacity(0.94))
            .foregroundStyle(scheme == .dark ? GtlColor.moonCream : GtlColor.nightInk)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}

struct LocationSettingsScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.text(
                "Location access is controlled in Settings. GTL needs While Using the App and Precise Location. After Start, recording continues on a locked screen and in the background until Stop, with the blue indicator visible. Force quitting the app stops it.",
                "A helyhozzáférést a Beállításokban lehet kezelni. A GTL-nek az app használata közben engedély és a Pontos hely kell. Az Indítás után a rögzítés zárolt képernyőn és háttérben is folytatódik a Leállításig, a kék jelzővel. Az app kényszerített bezárása leállítja."
            ))
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            Button(L10n.text("Open Settings", "Beállítások megnyitása")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(GtlPrimaryButton(color: GtlColor.hudTeal))
            .padding()
        }
        .navigationTitle(L10n.text("Location settings", "Helyzet beállítások"))
    }
}

struct ErrorLogScreen: View {
    @State private var text = ErrorLogStore.text()
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? L10n.text("No errors", "Nincs hiba") : text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(L10n.text("Error log", "Hibanapló"))
        .toolbar {
            Button(L10n.text("Clear", "Törlés")) {
                ErrorLogStore.clear()
                text = ""
            }
        }
    }
}
