import Foundation

struct Point: Codable, Identifiable {
    let date: Date, battery: Double, system: Double, segment: Int
    var id: Date { date }
}

/// Всё, что показывают панель, меню и виджеты. Приложение пишет снимок в файл, виджет читает.
struct Snapshot: Codable {
    var date = Date.now
    var battery = 0.0
    var system = 0.0
    var adapter = 0.0
    var rating: Int?
    var percent: Int?
    var remaining: TimeInterval?
    /// Средний ток за минуту. Подпись и время обязаны считаться из одного среднего,
    /// иначе время до нуля подпишется «до полной».
    var trend = 0.0
    var weak: Weak?
    var history: [Point] = []

    var timeLabel: String { trend > 0 ? "Until full" : "Remaining" }

    /// Точка раз в 30 с. Дыра больше 90 с — Mac спал: рвём линию, а не тянем её через сон.
    mutating func record(battery: Double, system: Double, at now: Date = .now) {
        let segment = history.last.map { now.timeIntervalSince($0.date) > 90 ? $0.segment + 1 : $0.segment } ?? 0
        history = history.filter { now.timeIntervalSince($0.date) < 3600 }
            + [Point(date: now, battery: battery, system: system, segment: segment)]
    }

    // MARK: - Файл

    /// App Group требует команды разработчика, а сборка подписана ad-hoc. Поэтому обычный файл:
    /// приложение пишет, виджету в песочнице эта папка открыта на чтение (см. entitlements в project.yml).
    static var file: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil } // NSHomeDirectory у виджета — контейнер
        return URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Library/Application Support/WattPeek/snapshot.json")
    }

    static func load() -> Snapshot? {
        file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    }

    func save() {
        guard let url = Self.file else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try JSONEncoder().encode(self).write(to: url, options: .atomic) }
        catch { NSLog("WattPeek: снимок не записан: %@", "\(error)") }
    }

    /// Для виджета: свежий снимок приложения, а если оно не запущено — прямое чтение с прежней историей.
    static func forWidget() -> Snapshot {
        var s = load() ?? Snapshot(date: .distantPast)
        guard Date.now.timeIntervalSince(s.date) > 120 else { return s }
        let p = readPower(nil), cap = capacity()
        s.date = .now
        s.battery = p?.battery ?? 0
        s.system = p?.system ?? 0
        s.adapter = p?.adapter ?? 0
        s.trend = p?.milliamps ?? 0
        s.rating = adapterRating()
        s.percent = batteryPercent()
        s.remaining = cap.flatMap { timeLeft(milliamps: s.trend, now: $0.now, full: $0.full) }
        s.weak = nil // нужна минута наблюдения
        s.history = s.history.filter { Date.now.timeIntervalSince($0.date) < 3600 }
        return s
    }
}
