import Charts
import SwiftUI

/// Что показывать: панель берёт из настроек, виджет — из своей конфигурации.
struct Display {
    var chart = true, warning = true, mac = true, adapter = true, charge = true, time = true
}

func stateColor(_ battery: Double) -> Color { isIdle(battery) ? .primary : battery > 0 ? .green : .orange }

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

struct Rows: View {
    let s: Snapshot
    let show: Display

    var body: some View {
        if show.mac { row("Mac", watts(s.system)) }
        if show.adapter { row(L("Adapter"), adapterText(s.adapter, s.rating)) }
        if show.charge { row(L("Charge"), percentText(s.percent)) }
        if show.time { row(L(s.timeLabel), durationText(s.remaining)) }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(minLength: 4); Text(value) }
            .lineLimit(1).minimumScaleFactor(0.6)
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

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(L("Last hour"))
                Spacer()
                Capsule().fill(.secondary).frame(width: 10, height: 1.5)
                Text("Mac")
            }
            .font(.caption2).foregroundStyle(.secondary)
            HistoryChart(points: points)
        }
    }
}

struct HistoryChart: View {
    let points: [Point]

    var body: some View {
        let end = points.last?.date ?? .now
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("t", p.date), y: .value("W", max(0, p.battery)), series: .value("s", "+\(p.segment)"), stacking: .unstacked)
                    .foregroundStyle(Color.green.opacity(0.7))
                AreaMark(x: .value("t", p.date), y: .value("W", min(0, p.battery)), series: .value("s", "-\(p.segment)"), stacking: .unstacked)
                    .foregroundStyle(Color.orange.opacity(0.7))
                LineMark(x: .value("t", p.date), y: .value("W", p.system), series: .value("s", "m\(p.segment)"))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            RuleMark(y: .value("W", 0)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartXScale(domain: end.addingTimeInterval(-3600)...end)
        // Явный масштаб: автоматический округляет до ±50 и сплющивает график.
        .chartYScale(domain: min(0, (points.map(\.battery).min() ?? 0) * 1.1)...max(5, (points.map { max($0.battery, $0.system) }.max() ?? 0) * 1.1))
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel().font(.system(size: 9)) } }
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

extension View {
    func localDirection() -> some View { environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight) }
}
