import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Настройки виджетов

struct OverviewIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Overview"
    @Parameter(title: "Show chart", default: true) var chart: Bool
    @Parameter(title: "Show weak adapter warning", default: true) var warning: Bool
    @Parameter(title: "Show update time", default: true) var updated: Bool
    @Parameter(title: "Charge", default: true) var charge: Bool
    @Parameter(title: "Time", default: true) var time: Bool
    @Parameter(title: "Mac", default: true) var mac: Bool
    @Parameter(title: "Adapter", default: true) var adapter: Bool
    @Parameter(title: "Temperature", default: true) var temperature: Bool
    @Parameter(title: "Battery health", default: true) var health: Bool

    var display: Display {
        Display(chart: chart, warning: warning, mac: mac, adapter: adapter, charge: charge, time: time,
                temperature: temperature, health: health)
    }
}

struct SimpleIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Power"
    @Parameter(title: "Show weak adapter warning", default: true) var warning: Bool
    @Parameter(title: "Show update time", default: true) var updated: Bool
}

/// Кнопка на виджете: после perform система перечитывает ленту вне суточного лимита.
struct RefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult { .result() }
}

// MARK: - Данные

struct Entry<I: WidgetConfigurationIntent>: TimelineEntry {
    let date: Date
    let s: Snapshot
    let config: I
}

struct Provider<I: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> Entry<I> { Entry(date: .now, s: .sample, config: I()) }
    func snapshot(for config: I, in context: Context) async -> Entry<I> {
        Entry(date: .now, s: context.isPreview ? .sample : .forWidget(), config: config)
    }
    func timeline(for config: I, in _: Context) async -> Timeline<Entry<I>> {
        Timeline(entries: [Entry(date: .now, s: .forWidget(), config: config)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

extension Snapshot {
    /// Для галереи виджетов: час, где сначала зарядка, потом работа от батареи.
    static var sample: Snapshot {
        var s = Snapshot(battery: 38.2, system: 21.4, adapter: 61.3, rating: 96, percent: 64, temperature: 36, cycles: 198, health: 92, remaining: 3900, trend: 3000)
        for i in 0..<120 {
            let x = Double(i) / 120
            s.record(battery: x < 0.45 ? -14 - 5 * sin(x * 22) : 46 - 18 * x + 2 * sin(x * 40), system: 18 + 5 * sin(x * 22),
                     percent: x < 0.45 ? 52 - Int(x * 20) : 43 + Int((x - 0.45) * 38),
                     at: s.date.addingTimeInterval(Double(i - 119) * 30))
        }
        return s
    }
}

// MARK: - Вид

struct StatusLine: View {
    let s: Snapshot
    let updated: Bool

    var body: some View {
        // Длинный перевод рядом со временем не помещается: тогда время уходит под него, а не режет слово.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { state; Spacer(minLength: 2); time }
            VStack(alignment: .leading, spacing: 0) { state.minimumScaleFactor(0.8); time }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private var state: some View { Text(status(s.battery)).lineLimit(1) }

    // Виджет не живой: время снимка честно говорит, насколько цифры свежие.
    @ViewBuilder private var time: some View { if updated { Text(s.date, style: .time).lineLimit(1).fixedSize() } }
}

struct RefreshButton: View {
    var body: some View {
        Button(intent: RefreshIntent()) { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)) }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L("Refresh"))
    }
}

struct Header: View {
    let s: Snapshot
    var size: CGFloat = 24
    let updated: Bool
    /// Без строки статуса: место уходит предупреждению, а время встаёт рядом с кнопкой.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Headline(battery: s.battery, size: size)
                Spacer(minLength: 0)
                if compact && updated { Text(s.date, style: .time).font(.caption2).foregroundStyle(.secondary).fixedSize() }
                RefreshButton()
            }
            if !compact { StatusLine(s: s, updated: updated) }
        }
    }
}

/// Строка для тесных размеров: значок, имя, значение.
struct CompactRow: View {
    let symbol: String, color: Color, name: String, value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(color).frame(width: 15).accessibilityHidden(true)
            Text(name).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).fontWeight(.semibold).fixedSize()
        }
        .font(.caption).lineLimit(1).minimumScaleFactor(0.6)
    }
}

struct CompactAdapter: View {
    let s: Snapshot
    var actual = true

    var body: some View {
        // Имя и «Не подключён» рядом не помещаются; что это адаптер, скажет значок.
        CompactRow(symbol: "powerplug.fill", color: .blue, name: L(s.rating == nil ? "Not connected" : "Adapter"),
                   value: s.rating.map { actual ? adapterShort(s.adapter, $0) : watts(Double($0), digits: 0) } ?? "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pair(L("Adapter"), adapterText(s.adapter, s.rating)))
    }
}

/// Значок с числом, без имени.
struct Chip: View {
    let symbol: String, color: Color, name: String, value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(color).frame(width: 13)
            Text(value).font(.caption).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(pair(name, value))
    }
}

struct TemperatureChip: View {
    let s: Snapshot
    var body: some View {
        if s.temperature != nil { Chip(symbol: "thermometer.medium", color: .secondary, name: L("Temperature"), value: temperatureText(s.temperature)) }
    }
}

struct HealthChip: View {
    let s: Snapshot
    var body: some View {
        if s.health != nil { Chip(symbol: "heart.fill", color: .pink, name: L("Battery health"), value: percentText(s.health)) }
    }
}

struct OverviewView: View {
    let s: Snapshot
    let show: Display
    let updated: Bool
    let family: WidgetFamily

    private var weak: Weak? { show.warning ? s.weak : nil }
    /// В большом виджете высота ограничена: у заряда полоса без графика.
    private var noChart: Display { var d = show; d.chart = false; return d }

    var body: some View {
        switch family {
        case .systemLarge:
            VStack(alignment: .leading, spacing: 6) {
                Header(s: s, size: 28, updated: updated)
                if let weak { WeakLabel(weak: weak) }
                if show.chart {
                    // Без подписи «Последний час»: высоты впритык.
                    if show.mac { HistoryChart(points: s.history, mac: false) } else { HistoryBlock(points: s.history) }
                }
                if show.charge || show.time { Divider(); ChargeBlock(s: s, show: noChart) }
                if show.mac { Divider(); MacBlock(s: s, chart: show.chart && weak == nil) }
                if show.adapter { Divider(); AdapterRow(s: s) }
                if chips { Divider(); chipLine }
                if !show.chart { Spacer(minLength: 0) }
            }
        case .systemMedium:
            HStack(spacing: 16) {
                facts
                if show.chart || chips {
                    VStack(alignment: .leading, spacing: 6) {
                        if show.chart { HistoryBlock(points: s.history) } else { Spacer(minLength: 0) }
                        if chips { chipLine }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        default:
            facts
        }
    }

    private var chips: Bool { (show.temperature && s.temperature != nil) || (show.health && s.health != nil) }

    private var chipLine: some View {
        HStack(spacing: 12) {
            if show.temperature { TemperatureChip(s: s) }
            if show.health { HealthChip(s: s) }
            if show.health, family == .systemLarge, let n = s.cycles {
                Text(pair(L("Cycle count"), n.formatted())).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(s: s, size: 24, updated: updated, compact: weak != nil)
            if show.charge { ChargeBar(percent: s.percent).padding(.vertical, 1) } else { Divider() }
            if show.charge { CompactRow(symbol: batterySymbol(s.percent), color: chargeColor(s.percent), name: L("Charge"), value: percentText(s.percent)) }
            if show.time { CompactRow(symbol: "clock", color: .secondary, name: L(s.timeLabel), value: durationText(s.remaining)) }
            if show.mac { CompactRow(symbol: "laptopcomputer", color: macColor, name: "Mac", value: watts(s.system)) }
            if show.adapter { CompactAdapter(s: s) }
            Spacer(minLength: 0)
            if let weak {
                // Значок в строке, а не отдельной колонкой: иначе длинный перевод не помещается.
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(weakText(weak))")
                    .font(.caption2).foregroundStyle(.orange).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PowerView: View {
    let s: Snapshot
    let warning: Bool, updated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: stateSymbol(s.battery)).font(.system(size: 24)).foregroundStyle(stateColor(s.battery))
                Spacer()
                RefreshButton()
            }
            Spacer(minLength: 0)
            Text(watts(s.battery, signed: true)).font(.system(size: 34, weight: .semibold))
                .foregroundStyle(stateColor(s.battery)).lineLimit(1).minimumScaleFactor(0.5)
            StatusLine(s: s, updated: updated)
            if warning, let weak = s.weak {
                Text(weakText(weak)).font(.caption2).foregroundStyle(.orange).lineLimit(2).minimumScaleFactor(0.8)
            } else {
                ChargeBar(percent: s.percent)
                HStack(spacing: 4) {
                    Text(percentText(s.percent)).fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Text(durationText(s.remaining)).foregroundStyle(.secondary).accessibilityLabel(pair(L(s.timeLabel), durationText(s.remaining)))
                }
                .font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

struct ChartView: View {
    let s: Snapshot
    let warning: Bool, updated: Bool
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(s: s, size: family == .systemLarge ? 30 : 20, updated: updated)
            if warning, let weak = s.weak { WeakLabel(weak: weak) }
            HistoryChart(points: s.history, mac: family != .systemLarge)
            if family == .systemLarge {
                Divider()
                VStack(spacing: 8) {
                    PanelRow(symbol: batterySymbol(s.percent), color: chargeColor(s.percent), name: L("Charge"), value: percentText(s.percent))
                    Sparkline(points: s.history, value: \.percentValue, top: 100, label: percentText(100), color: .green)
                }
                Divider()
                MacBlock(s: s, chart: true)
            }
        }
    }
}

struct BatteryView: View {
    let s: Snapshot
    let warning: Bool, updated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 0) {
                Gauge(value: Double(s.percent ?? 0), in: 0...100) { EmptyView() } currentValueLabel: {
                    Text(percentText(s.percent)).font(.system(size: 14, weight: .semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(chargeColor(s.percent))
                VStack(alignment: .leading, spacing: 6) {
                    TemperatureChip(s: s)
                    HealthChip(s: s)
                }
                .padding(.top, 6).padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                RefreshButton()
            }
            Spacer(minLength: 0)
            CompactRow(symbol: "clock", color: .secondary, name: L(s.timeLabel), value: durationText(s.remaining))
            CompactAdapter(s: s, actual: false)
            if warning, let weak = s.weak {
                Text(weakText(weak)).font(.caption2).foregroundStyle(.orange).lineLimit(2).minimumScaleFactor(0.8)
            } else {
                StatusLine(s: s, updated: updated)
            }
        }
    }
}

struct Frame<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View {
        content(family)
            .monospacedDigit()
            .localDirection()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Виджеты

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "overview", intent: OverviewIntent.self, provider: Provider<OverviewIntent>()) { e in
            Frame { OverviewView(s: e.s, show: e.config.display, updated: e.config.updated, family: $0) }
        }
        .configurationDisplayName("Overview")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PowerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "power", intent: SimpleIntent.self, provider: Provider<SimpleIntent>()) { e in
            Frame { _ in PowerView(s: e.s, warning: e.config.warning, updated: e.config.updated) }
        }
        .configurationDisplayName("Power")
        .supportedFamilies([.systemSmall])
    }
}

struct ChartWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "chart", intent: SimpleIntent.self, provider: Provider<SimpleIntent>()) { e in
            Frame { ChartView(s: e.s, warning: e.config.warning, updated: e.config.updated, family: $0) }
        }
        .configurationDisplayName("Chart")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Вид "battery" был в 1.1 без настроек. Имя не переиспользовать: стоящий на столе виджет сломается (CHSError 1103).
struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "charge", intent: SimpleIntent.self, provider: Provider<SimpleIntent>()) { e in
            Frame { _ in BatteryView(s: e.s, warning: e.config.warning, updated: e.config.updated) }
        }
        .configurationDisplayName("Battery")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct WattPeekWidgets: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        PowerWidget()
        ChartWidget()
        BatteryWidget()
    }
}
