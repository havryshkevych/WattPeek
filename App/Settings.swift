import AppKit
import ServiceManagement
import SwiftUI

enum Settings {
    static let defaults: [String: Any] = [
        "showPanel": true, "onTop": false, "showIcon": true, "showWatts": true, "iconStyle": IconStyle.auto.rawValue,
        "showChart": true, "showWarning": true, "rowMac": true, "rowAdapter": true, "rowCharge": true, "rowTime": true,
        "rowTemperature": true, "rowHealth": true,
    ]

    static func on(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    static var display: Display {
        Display(chart: on("showChart"), warning: on("showWarning"), mac: on("rowMac"),
                adapter: on("rowAdapter"), charge: on("rowCharge"), time: on("rowTime"),
                temperature: on("rowTemperature"), health: on("rowHealth"))
    }

    static var iconStyle: IconStyle { IconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .auto }
}

enum IconStyle: String, CaseIterable {
    case auto, bolt, battery, plug, gauge, laptop

    /// Имя SF Symbol; auto и battery меняются вместе с состоянием.
    func symbol(battery: Double, percent: Int?) -> String {
        switch self {
        case .auto: return stateSymbol(battery)
        case .bolt: return "bolt"
        case .battery: return batterySymbol(percent)
        case .plug: return "powerplug.fill"
        case .gauge: return "gauge.with.dots.needle.50percent"
        case .laptop: return "laptopcomputer"
        }
    }

    /// В списке выбора: у auto своя картинка, иначе его не отличить от молнии.
    var sample: String { self == .auto ? "wand.and.stars" : symbol(battery: 1, percent: 75) }

    var label: String {
        switch self {
        case .auto: return L("Automatic")
        case .bolt: return L("Power")
        case .battery: return L("Battery")
        case .plug: return L("Adapter")
        case .gauge: return L("Chart")
        case .laptop: return "Mac"
        }
    }
}

struct SettingsView: View {
    @AppStorage("showIcon") private var showIcon = true
    @AppStorage("iconStyle") private var iconStyle = IconStyle.auto.rawValue
    @AppStorage("showWatts") private var showWatts = true
    @AppStorage("showPanel") private var showPanel = true
    @AppStorage("onTop") private var onTop = false
    @AppStorage("showChart") private var showChart = true
    @AppStorage("showWarning") private var showWarning = true
    @AppStorage("rowMac") private var rowMac = true
    @AppStorage("rowAdapter") private var rowAdapter = true
    @AppStorage("rowCharge") private var rowCharge = true
    @AppStorage("rowTime") private var rowTime = true
    @AppStorage("rowTemperature") private var rowTemperature = true
    @AppStorage("rowHealth") private var rowHealth = true
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section(L("General")) {
                Toggle(L("Open at Login"), isOn: Binding(get: { login }, set: setLogin))
                Toggle(L("Show weak adapter warning"), isOn: $showWarning)
            }
            Section(L("Menu Bar")) {
                Toggle(L("Show icon"), isOn: $showIcon)
                Picker(L("Icon"), selection: $iconStyle) {
                    ForEach(IconStyle.allCases, id: \.rawValue) { style in
                        Image(systemName: style.sample).accessibilityLabel(style.label).help(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!showIcon)
                // Без иконки ватты обязательны: иначе до меню и настроек не добраться.
                Toggle(L("Show watts"), isOn: showIcon ? $showWatts : .constant(true)).disabled(!showIcon)
            }
            Section(L("Panel")) {
                Toggle(L("Panel on desktop"), isOn: $showPanel)
                Group {
                    Toggle(L("Panel above all windows"), isOn: $onTop)
                    Toggle(L("Show chart"), isOn: $showChart)
                    Toggle(L("Charge"), isOn: $rowCharge)
                    Toggle(L("Time"), isOn: $rowTime)
                    Toggle("Mac", isOn: $rowMac)
                    Toggle(L("Adapter"), isOn: $rowAdapter)
                    Toggle(L("Temperature"), isOn: $rowTemperature)
                    Toggle(L("Battery health"), isOn: $rowHealth)
                }
                .disabled(!showPanel)
            }
        }
        .formStyle(.grouped)
        .localDirection()
        .frame(width: 420)
        .fixedSize()
    }

    private func setLogin(_ on: Bool) {
        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
        catch { NSAlert(error: error).runModal() }
        login = SMAppService.mainApp.status == .enabled
    }
}

final class SettingsWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        contentViewController = NSHostingController(rootView: SettingsView())
        title = "WattPeek"
        isReleasedWhenClosed = false
        center()
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
