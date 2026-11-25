import AppKit
import ServiceManagement
import WidgetKit

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let smc = SMC()
    private var samples: [Sample] = []
    private var ticks = 0
    private var widgetState = ""
    private var layoutState = ""
    private var menuOpened = (at: Date.distantPast, mouse: NSPoint.zero)
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let rows = (0..<8).map { _ in NSMenuItem(title: "—", action: nil, keyEquivalent: "") }
    private let model = Model()
    private lazy var panel = Panel(model: model)
    private lazy var settings = SettingsWindow()

    func applicationDidFinishLaunching(_: Notification) {
        UserDefaults.standard.register(defaults: Settings.defaults)
        // График переживает перезапуск; остальное в снимке заменит первый же tick.
        model.s.history = (Snapshot.load()?.history ?? []).filter { Date.now.timeIntervalSince($0.date) < 3600 }

        let menu = NSMenu()
        menu.userInterfaceLayoutDirection = isRTL ? .rightToLeft : .leftToRight
        rows.forEach(menu.addItem)
        menu.addItem(.separator())
        let open = NSMenuItem(title: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
        item.button?.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular)

        // У программы без Dock меню не видно, но без него окно настроек не закрыть по ⌘W.
        let hidden = NSMenu(), top = NSMenuItem()
        top.submenu = NSMenu()
        top.submenu?.addItem(withTitle: "", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        hidden.addItem(top)
        NSApp.mainMenu = hidden

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.2 // система склеивает пробуждения, батарея целее
        RunLoop.main.add(timer, forMode: .common) // .common — чтобы цифры шли и при открытом меню
        tick()
        applySettings()
    }

    /// Повторный запуск из Finder или клик по виджету — открыть настройки.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        settings.present()
        return false
    }

    // Двойной клик по иконке — показать или убрать панель. Первый клик сразу открывает меню, второй его закрывает:
    // так одинарный не ждёт, не станет ли он двойным.
    func menuWillOpen(_: NSMenu) { menuOpened = (.now, NSEvent.mouseLocation) }

    func menuDidClose(_: NSMenu) {
        let mouse = NSEvent.mouseLocation
        guard Date.now.timeIntervalSince(menuOpened.at) < NSEvent.doubleClickInterval,
              hypot(mouse.x - menuOpened.mouse.x, mouse.y - menuOpened.mouse.y) < 5 else { return }
        UserDefaults.standard.set(!Settings.on("showPanel"), forKey: "showPanel") // дальше сработает applySettings
    }

    @objc private func openSettings() { settings.present() }

    private func applySettings() {
        panel.onTop = Settings.on("onTop")
        if !Settings.on("showPanel") { panel.orderOut(nil) } else if !panel.isVisible { panel.orderFrontRegardless() }
        render(force: true)
    }

    private func tick() {
        guard let p = readPower(smc) else {
            item.button?.title = L("No data")
            return
        }
        // Сменилось питание — старые средние уже не про то.
        if let last = samples.last, (last.adapter > 1) != (p.adapter > 1) { samples.removeAll() }
        samples = (samples + [p]).suffix(30) // минута при опросе раз в 2 с
        func mean(_ k: KeyPath<Sample, Double>, _ n: Int) -> Double {
            let v = samples.suffix(n).map { $0[keyPath: k] }
            return v.reduce(0, +) / Double(v.count)
        }
        var s = model.s
        s.date = .now
        s.battery = mean(\.battery, 3) // цифры на экране: среднее за 6 с, ток скачет
        s.system = mean(\.system, 3)
        s.adapter = mean(\.adapter, 3)
        s.rating = adapterRating()
        s.percent = batteryPercent()
        s.temperature = batteryTemperature(smc)
        s.cycles = cycleCount()
        // Время и предупреждение — по минуте, и не раньше 20 с данных.
        let ready = samples.count >= 10
        s.trend = mean(\.milliamps, 30)
        s.remaining = ready ? capacity().flatMap { timeLeft(milliamps: s.trend, now: $0.now, full: $0.full) } : nil
        s.weak = ready ? weakAdapter(rating: s.rating, adapter: mean(\.adapter, 30), battery: mean(\.battery, 30),
                                     percent: s.percent, remaining: s.remaining) : nil
        if ticks % 43_200 == 0 { updateHealth() } // раз в сутки: меняется на процент за месяцы
        ticks += 1
        let point = ticks % 15 == 0
        if point { s.record(battery: mean(\.battery, 15), system: mean(\.system, 15), percent: s.percent) }
        model.s = s
        render()

        // Виджеты: сразу при смене зарядки, процента или предупреждения и раз в 5 минут.
        // Чаще бесполезно: систему обновления фоновых виджетов урезает macOS.
        let state = "\(s.rating ?? 0)/\(s.percent ?? 0)/\(warning?.rawValue ?? "")"
        let changed = state != widgetState || ticks % 150 == 0
        if point || changed {
            var saved = s
            saved.weak = warning
            saved.save()
        }
        if changed { widgetState = state; WidgetCenter.shared.reloadAllTimelines() }
    }

    private func updateHealth() {
        DispatchQueue.global(qos: .utility).async {
            guard let health = batteryHealth() else { return }
            DispatchQueue.main.async { self.model.s.health = health }
        }
    }

    private var warning: Weak? { Settings.on("showWarning") ? model.s.weak : nil }

    private func render(force: Bool = false) {
        let s = model.s
        let icon = Settings.on("showIcon")
        item.button?.title = !icon || Settings.on("showWatts") ? watts(s.battery, signed: true) : ""
        item.button?.imagePosition = item.button?.title.isEmpty == true ? .imageOnly : .imageLeading
        item.button?.image = icon ? NSImage(
            systemSymbolName: warning == nil ? Settings.iconStyle.symbol(battery: s.battery, percent: s.percent) : "exclamationmark.triangle",
            accessibilityDescription: warning.map(weakText) ?? status(s.battery)) : nil
        rows[0].title = pair(status(s.battery), watts(s.battery))
        rows[1].title = pair("Mac", watts(s.system))
        rows[2].title = pair(L("Adapter"), adapterText(s.adapter, s.rating))
        rows[3].title = pair(L("Charge"), percentText(s.percent))
        rows[4].title = pair(L(s.timeLabel), durationText(s.remaining))
        rows[5].title = pair(L("Temperature"), temperatureText(s.temperature))
        rows[6].title = pair(L("Battery health"), percentText(s.health))
        rows[7].title = warning.map(weakText) ?? ""
        rows[7].isHidden = warning == nil

        // Закрытую окнами панель не перерисовываем, кроме смены настроек.
        guard force || panel.occlusionState.contains(.visible) else { return }
        model.objectWillChange.send()
        // Высота меняется только от предупреждения, настроек и появления подписей и графиков; мерить её каждый раз незачем.
        let layout = "\(Settings.display)\(s.weak?.rawValue ?? "")\(s.rating == nil)\(s.cycles == nil)\(s.history.isEmpty)"
        if layout != layoutState { layoutState = layout; DispatchQueue.main.async { self.panel.fit() } }
    }
}

if CommandLine.arguments.contains("--check") {
    let us = Locale(identifier: "en_US"), ru = Locale(identifier: "ru_RU")
    assert(watts(1.04, signed: true, locale: us) == "+1.0W" || watts(1.04, signed: true, locale: us) == "+1.0 W")
    assert(watts(-14.26, signed: true, locale: ru).contains("14,3") && watts(-14.26, signed: true, locale: ru).hasSuffix("Вт"))
    assert(watts(-0.01, signed: true, locale: us).hasPrefix("0.0"))
    assert(timeLeft(milliamps: 100, now: 500, full: 600) == 3600 && timeLeft(milliamps: -250, now: 500, full: 600) == 7200)
    assert(timeLeft(milliamps: 5, now: 500, full: 600) == nil)
    assert(weakAdapter(rating: 20, adapter: 18.2, battery: 1, percent: 6, remaining: 90_000) == .barely)
    assert(weakAdapter(rating: 20, adapter: 18.2, battery: -1, percent: 6, remaining: 9_000) == .draining)
    assert(weakAdapter(rating: 20, adapter: 18.2, battery: 9, percent: 50, remaining: 9_000) == nil)
    assert(weakAdapter(rating: 140, adapter: 30, battery: -2, percent: 60, remaining: 9_000) == nil) // не выжат
    assert(weakAdapter(rating: nil, adapter: 0, battery: -9, percent: 6, remaining: 900) == nil)
    assert(temperatureText(36.4, locale: ru).hasPrefix("36") && temperatureText(36.4, locale: us).hasPrefix("98") && temperatureText(nil) == "—")
    assert(scaleTop(0) == 10 && scaleTop(25) == 25 && scaleTop(26) == 50 && scaleTop(201) == 300)
    assert(parseHealth(Data(#"{"SPPowerDataType":[{"_name":"x"},{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"82%"}}]}"#.utf8)) == 82)
    assert(parseHealth(Data("{}".utf8)) == nil && parseHealth(Data()) == nil)
    assert((try? JSONDecoder().decode(Point.self, from: Data(#"{"date":0,"battery":1,"system":1,"segment":0}"#.utf8))) != nil) // снимок 1.3
    var m = Snapshot(battery: 0.2, trend: -32) // мгновенно заряжается, за минуту разряжается: подпись — по минуте
    assert(m.timeLabel == "Remaining")
    let t = Date.now
    for (offset, _) in [(-4000, 0), (-200, 0), (-170, 0), (0, 0)] { m.record(battery: 1, system: 1, at: t.addingTimeInterval(Double(offset))) }
    assert(m.history.count == 3 && m.history.map(\.segment) == [1, 1, 2]) // старше часа выпало, сон рвёт линию
    assert((try? JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(m)))?.history.count == 3)
    assert(NSImage(systemSymbolName: IconStyle.auto.sample, accessibilityDescription: nil) != nil)
    for style in IconStyle.allCases { for pc in [nil, 0, 12, 13, 50, 99, 100] { for b in [-5.0, 0, 5] {
        let name = style.symbol(battery: b, percent: pc)
        assert(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "нет символа \(name)")
    } } }
    let saved = Snapshot.load() // настоящую историю вернём на место
    m.save()
    assert(Snapshot.load()?.history.count == 3, "снимок не записан")
    if let saved { saved.save() } else { try? FileManager.default.removeItem(at: Snapshot.file!) }
    for (name, s) in [("SMC", SMC().flatMap(readPower)), ("IORegistry", readPower(nil))] {
        guard let s else { fatalError("\(name) не читается") }
        print(name, watts(s.battery, signed: true), "| адаптер", watts(s.adapter), "| Mac", watts(s.system))
    }
    guard let cap = capacity() else { fatalError("ёмкость не читается") }
    print("температура", temperatureText(batteryTemperature(SMC())), "| циклы", cycleCount() ?? -1, "| здоровье", percentText(batteryHealth()))
    print("ёмкость", cap, "| автозапуск", SMAppService.mainApp.status == .enabled)
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
