import Foundation
import IOKit
import IOKit.ps

struct Sample {
    var battery: Double   // Вт: > 0 заряжается, < 0 разряжается
    var milliamps: Double // тот же ток, мА, со знаком
    var adapter: Double   // Вт от блока питания
    var system: Double    // Вт потребляет сам Mac
}

// MARK: - Чтение

func batteryProperty(_ key: String) -> Any? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

private func number(_ key: String) -> Double? { (batteryProperty(key) as? NSNumber).map { Double($0.int64Value) } }

/// SMC — живые данные; в песочнице (App Store, виджет) он закрыт, тогда IORegistry с обновлением раз в минуту.
func readPower(_ smc: SMC?) -> Sample? {
    if let smc, let mA = smc.read("B0AC"), let mV = smc.read("B0AV") {
        return Sample(battery: mA * mV / 1_000_000, milliamps: mA,
                      adapter: smc.read("PDTR") ?? 0, system: smc.read("PSTR") ?? 0)
    }
    guard let mA = number("Amperage"), let mV = number("Voltage") else { return nil }
    let t = batteryProperty("PowerTelemetryData") as? [String: NSNumber]
    return Sample(battery: mA * mV / 1_000_000, milliamps: mA,
                  adapter: (t?["SystemPowerIn"]?.doubleValue ?? 0) / 1000,
                  system: (t?["SystemLoad"]?.doubleValue ?? 0) / 1000)
}

/// Остаток и полная ёмкость, мА·ч.
func capacity() -> (now: Double, full: Double)? {
    // Новые macOS держат это в BatteryData, старые — на верхнем уровне.
    let d = batteryProperty("BatteryData") as? [String: Any]
    func value(_ key: String) -> Double? { (d?[key] as? NSNumber)?.doubleValue ?? number(key) }
    guard let now = value("AppleRawCurrentCapacity"), let full = value("AppleRawMaxCapacity"), full > 0 else { return nil }
    return (now, full)
}

func batteryPercent() -> Int? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
        return d[kIOPSCurrentCapacityKey] as? Int
    }
    return nil
}

/// Номинал подключённого блока питания; nil — не подключён.
func adapterRating() -> Int? {
    (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])?[kIOPSPowerAdapterWattsKey] as? Int
}

// MARK: - Выводы

/// Секунд до полной (ток > 0) или до нуля (ток < 0); nil — ток слишком мал, чтобы говорить о времени.
// ponytail: линейная оценка; после ~80% зарядка замедляется, и время занижено. Точнее — кривая по истории зарядок.
func timeLeft(milliamps mA: Double, now: Double, full: Double) -> TimeInterval? {
    guard abs(mA) >= 20 else { return nil }
    return max(0, mA > 0 ? full - now : now) / abs(mA) * 3600
}

enum Weak: String, Codable { case draining, barely }

/// Адаптер выжат почти до номинала, а батарее не достаётся. На входе средние, иначе флаг мигает.
func weakAdapter(rating: Int?, adapter: Double, battery: Double, percent: Int?, remaining: TimeInterval?) -> Weak? {
    guard let rating, rating > 0, adapter >= 0.85 * Double(rating), let percent, percent < 80 else { return nil }
    if battery < -0.5 { return .draining }
    return (remaining ?? .infinity) > 4 * 3600 ? .barely : nil
}

func weakText(_ w: Weak) -> String {
    L(w == .draining ? "Weak adapter: battery is draining" : "Weak adapter: battery barely charging")
}

// MARK: - Текст

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Направление письма языка, на котором реально показан интерфейс.
let isRTL = Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en").characterDirection == .rightToLeft

func pair(_ name: String, _ value: String) -> String { String(format: L("%1$@: %2$@"), name, value) }

/// Число, знак и «Вт/W/واط» — по языку и региону macOS.
func watts(_ v: Double, digits: Int = 1, signed: Bool = false, locale: Locale = .current) -> String {
    // |P| < 0.05 округлится до нуля, знак при нём не нужен
    let number = FloatingPointFormatStyle<Double>(locale: locale).precision(.fractionLength(digits))
        .sign(strategy: signed && !isIdle(v) ? .always(includingZero: false) : .never)
    let text = Measurement(value: v, unit: UnitPower.watts).formatted(
        .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: number).locale(locale))
    return isRTL ? "\u{2068}\(text)\u{2069}" : text // изоляция: иначе в RTL-строке «3.6 W» станет «W 3.6»
}

func isIdle(_ battery: Double) -> Bool { abs(battery) < 0.05 }

func status(_ battery: Double) -> String {
    L(isIdle(battery) ? "Battery idle" : battery > 0 ? "Battery charging" : "Battery discharging")
}

func adapterText(_ actual: Double, _ rating: Int?) -> String {
    rating.map { "\(watts(actual)) / \(watts(Double($0), digits: 0))" } ?? L("Not connected")
}

func percentText(_ p: Int?) -> String { p.map { $0.formatted(.percent) } ?? "—" }

func durationText(_ t: TimeInterval?) -> String {
    guard let t else { return "—" }
    let f = DateComponentsFormatter()
    f.unitsStyle = .abbreviated
    f.allowedUnits = t < 3600 ? [.minute] : [.hour, .minute]
    let day: TimeInterval = 24 * 3600
    return t > day ? "> " + (f.string(from: day) ?? "") : "≈ " + (f.string(from: max(60, t)) ?? "—")
}

func stateSymbol(_ battery: Double) -> String {
    isIdle(battery) ? "powerplug" : battery > 0 ? "bolt.fill" : "arrow.down"
}
