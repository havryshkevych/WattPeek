import Charts
import SwiftUI

/// Что показывать: панель берёт из настроек, виджет — из своей конфигурации.
struct Display {
    var chart = true, warning = true, mac = true, adapter = true, charge = true, time = true
    var temperature = true, health = true // виджетам, кроме большого и среднего обзора, не хватает места
}

func stateColor(_ battery: Double) -> Color { isIdle(battery) ? .primary : battery > 0 ? .green : .orange }

/// Оранжевый занят разрядом и предупреждениями, поэтому Mac фиолетовый.
let macColor = Color.purple

func chargeColor(_ percent: Int?) -> Color { (percent ?? 100) <= 20 ? .orange : .green }

struct Headline: View {
    let battery: Double
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: size * 0.2) {
            Image(systemName: stateSymbol(battery)).font(.system(size: size * 0.6))
            Text(watts(battery, signed: true)).font(.system(size: size, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .foregroundStyle(stateColor(battery))
    }
}

// MARK: - Блоки панели и больших виджетов

struct PanelRow: View {
    let symbol: String, color: Color, name: String
    var detail: String?
    let value: String
    var muted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(color)
                .frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout).lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }
            }
            Spacer(minLength: 4)
            Text(value).font(muted ? .callout : .system(size: 15, weight: .semibold)).foregroundStyle(muted ? .secondary : .primary).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Не ProgressView: в неактивном окне система красит его серым, а панель активной не бывает.
struct ChargeBar: View {
    let percent: Int?

    var body: some View {
        let percent = percent ?? 0
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if percent > 0 { Capsule().fill(chargeColor(percent)).frame(width: max(4, g.size.width * CGFloat(min(100, percent)) / 100)) }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

extension Point {
    var percentValue: Double? { percent.map(Double.init) }
    var macValue: Double? { system }
}

/// Последний час одной величины; пунктир сверху — верх шкалы.
struct Sparkline: View, Equatable {
    let points: [Point]
    let value: KeyPath<Point, Double?>
    let top: Double
    let label: String
    let color: Color

    var body: some View {
        let end = points.last?.date ?? .now
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                DashedLine().stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])).frame(height: 1)
            }
            chart(end: end)
        }
        .accessibilityHidden(true)
    }

    private func chart(end: Date) -> some View {
        Chart {
            ForEach(points) { p in
                if let v = p[keyPath: value] {
                    AreaMark(x: .value("t", p.date), y: .value("v", v), series: .value("s", p.segment), stacking: .unstacked)
                        .foregroundStyle(color.opacity(0.15))
                    LineMark(x: .value("t", p.date), y: .value("v", v), series: .value("s", p.segment))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-3600)...end)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .frame(height: 22)
    }
}

struct DashedLine: Shape {
    func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}

struct ChargeBlock: View {
    let s: Snapshot
    let show: Display

    var body: some View {
        if show.charge {
            VStack(spacing: 8) {
                PanelRow(symbol: batterySymbol(s.percent), color: chargeColor(s.percent), name: L("Charge"),
                         detail: show.time ? pair(L(s.timeLabel), durationText(s.remaining)) : nil, value: percentText(s.percent))
                ChargeBar(percent: s.percent)
                if show.chart { Sparkline(points: s.history, value: \.percentValue, top: 100, label: percentText(100), color: .green).equatable() }
            }
        } else if show.time {
            PanelRow(symbol: "clock", color: .secondary, name: L(s.timeLabel), value: durationText(s.remaining))
        }
    }
}

struct MacBlock: View {
    let s: Snapshot
    let chart: Bool

    var body: some View {
        VStack(spacing: 8) {
            PanelRow(symbol: "laptopcomputer", color: macColor, name: "Mac", value: watts(s.system))
            if chart {
                let top = scaleTop(s.history.map(\.system).max() ?? 0)
                Sparkline(points: s.history, value: \.macValue, top: top, label: watts(top, digits: 0), color: macColor).equatable()
            }
        }
    }
}

struct AdapterRow: View {
    let s: Snapshot

    var body: some View {
        PanelRow(symbol: "powerplug.fill", color: .blue, name: L("Adapter"),
                 detail: s.rating.map { String(format: L("max. %@"), watts(Double($0), digits: 0)) },
                 value: s.rating == nil ? L("Not connected") : watts(s.adapter), muted: s.rating == nil)
    }
}

struct WeakLabel: View {
    let weak: Weak

    var body: some View {
        Label(weakText(weak), systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

struct HistoryBlock: View {
    let points: [Point]
    var mac = true

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(L("Last hour"))
                Spacer()
                if mac {
                    Capsule().fill(macColor).frame(width: 10, height: 1.5)
                    Text("Mac")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            HistoryChart(points: points, mac: mac).equatable()
        }
    }
}

/// Equatable: точка приходит раз в 30 с, а панель перерисовывается раз в 2.
struct HistoryChart: View, Equatable {
    let points: [Point]
    var mac = true

    var body: some View {
        let end = points.last?.date ?? .now
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("t", p.date), y: .value("W", max(0, p.battery)), series: .value("s", "+\(p.segment)"), stacking: .unstacked)
                    .foregroundStyle(Color.green.opacity(0.7))
                AreaMark(x: .value("t", p.date), y: .value("W", min(0, p.battery)), series: .value("s", "-\(p.segment)"), stacking: .unstacked)
                    .foregroundStyle(Color.orange.opacity(0.7))
                if mac {
                    LineMark(x: .value("t", p.date), y: .value("W", p.system), series: .value("s", "m\(p.segment)"))
                        .foregroundStyle(macColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
            RuleMark(y: .value("W", 0)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartXScale(domain: end.addingTimeInterval(-3600)...end)
        // Явный масштаб: автоматический округляет до ±50 и сплющивает график.
        .chartYScale(domain: min(0, (points.map(\.battery).min() ?? 0) * 1.1)...max(5, (points.map { mac ? max($0.battery, $0.system) : $0.battery }.max() ?? 0) * 1.1))
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel().font(.system(size: 9)) } }
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

extension View {
    func localDirection() -> some View { environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight) }
}
