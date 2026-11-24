import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Настройки виджетов

struct OverviewIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Overview"
    @Parameter(title: "Show chart", default: true) var chart: Bool
    @Parameter(title: "Show weak adapter warning", default: true) var warning: Bool
    @Parameter(title: "Show update time", default: true) var updated: Bool
    @Parameter(title: "Mac", default: true) var mac: Bool
    @Parameter(title: "Adapter", default: true) var adapter: Bool
    @Parameter(title: "Charge", default: true) var charge: Bool
    @Parameter(title: "Time", default: true) var time: Bool

    var display: Display { Display(chart: chart, warning: warning, mac: mac, adapter: adapter, charge: charge, time: time) }
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
        var s = Snapshot(battery: 38.2, system: 21.4, adapter: 61.3, rating: 96, percent: 64, remaining: 3900, trend: 3000)
        for i in 0..<120 {
            let x = Double(i) / 120
            s.record(battery: x < 0.45 ? -14 - 5 * sin(x * 22) : 46 - 18 * x + 2 * sin(x * 40), system: 18 + 5 * sin(x * 22),
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

struct OverviewView: View {
    let s: Snapshot
    let show: Display
    let updated: Bool
    let family: WidgetFamily

    private var weak: Weak? { show.warning ? s.weak : nil }

    var body: some View {
        switch family {
        case .systemLarge:
            VStack(alignment: .leading, spacing: 8) {
                Header(s: s, size: 34, updated: updated)
                Divider()
                Rows(s: s, show: show)
                if let weak { WeakLabel(weak: weak) }
                if show.chart { HistoryBlock(points: s.history).padding(.top, 4) } else { Spacer(minLength: 0) }
            }
        case .systemMedium:
            HStack(spacing: 14) {
                facts(size: 24)
                if show.chart { HistoryBlock(points: s.history) }
            }
        default:
            facts(size: 24)
        }
    }

    private func facts(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(s: s, size: size, updated: updated, compact: weak != nil)
            Divider()
            Rows(s: s, show: show).font(.caption)
            Spacer(minLength: 0)
            if let weak {
                // Значок в строке, а не отдельной колонкой: иначе длинный перевод не помещается.
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(weakText(weak))")
                    .font(.caption2).foregroundStyle(.orange).lineLimit(3).fixedSize(horizontal: false, vertical: true)
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
            HStack {
                Image(systemName: stateSymbol(s.battery)).font(.system(size: 26)).foregroundStyle(stateColor(s.battery))
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
                Text(pair(L(s.timeLabel), durationText(s.remaining))).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

struct ChartView: View {
    let s: Snapshot
    let warning: Bool, updated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(s: s, size: 20, updated: updated)
            if warning, let weak = s.weak { WeakLabel(weak: weak) }
            HistoryChart(points: s.history)
        }
    }
}

struct BatteryView: View {
    let s: Snapshot
    let warning: Bool, updated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Gauge(value: Double(s.percent ?? 0), in: 0...100) { EmptyView() } currentValueLabel: {
                    Text(percentText(s.percent)).font(.system(size: 14, weight: .semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint((s.percent ?? 100) <= 20 ? .orange : .green)
                Spacer(minLength: 0)
                RefreshButton()
            }
            Spacer(minLength: 0)
            Text(pair(L(s.timeLabel), durationText(s.remaining))).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            Text(pair(L("Adapter"), s.rating.map { watts(Double($0), digits: 0) } ?? L("Not connected")))
                .font(.caption).lineLimit(1).minimumScaleFactor(0.7)
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
            Frame { _ in ChartView(s: e.s, warning: e.config.warning, updated: e.config.updated) }
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
