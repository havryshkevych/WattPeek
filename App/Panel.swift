import AppKit
import SwiftUI

/// Без @Published: App шлёт objectWillChange одним разом и только когда панель видна.
final class Model: ObservableObject {
    var s = Snapshot()
}

struct PanelView: View {
    @ObservedObject var model: Model

    var body: some View {
        let s = model.s, show = Settings.display
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Headline(battery: s.battery)
                Text(status(s.battery)).font(.caption).foregroundStyle(.secondary)
            }
            if show.mac || show.adapter || show.charge || show.time {
                Divider()
                Rows(s: s, show: show).font(.callout)
            }
            if show.warning, let weak = s.weak { WeakLabel(weak: weak) }
            if show.chart { HistoryBlock(points: s.history).frame(height: 96).padding(.top, 4) }
        }
        .monospacedDigit()
        .localDirection()
        .padding(14)
        .frame(width: Panel.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Панель тащится за любое место.
private final class DragHostingView: NSHostingView<PanelView> {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

final class Panel: NSPanel {
    static let width: CGFloat = 220
    private let host: DragHostingView

    init(model: Model) {
        let host = DragHostingView(rootView: PanelView(model: model))
        self.host = host
        let size = host.fittingSize
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        // maskImage, а не layer.cornerRadius: слой не обрезает размытие за окном, и торчат белые уголки.
        let mask = NSImage(size: NSSize(width: 37, height: 37), flipped: false) {
            NSBezierPath(roundedRect: $0, xRadius: 18, yRadius: 18).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        mask.resizingMode = .stretch
        blur.maskImage = mask
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        contentView = blur

        // Прошлое место; если его нет или тот монитор отключён — правый верхний угол.
        let restored = setFrameUsingName("Panel")
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !(restored && onScreen), let area = NSScreen.main?.visibleFrame {
            setFrame(NSRect(x: area.maxX - Self.width - 20, y: area.maxY - size.height - 20, width: Self.width, height: size.height), display: false)
        }
        fit()
        setFrameAutosaveName("Panel")
    }

    /// Высота по содержимому; верхний край стоит на месте.
    func fit() {
        // Меряем свежей копией: показанная отдаёт размер прошлого кадра. Вызывается редко, копия дёшева.
        let fresh = NSHostingView(rootView: PanelView(model: host.rootView.model))
        let size = NSSize(width: Self.width, height: fresh.fittingSize.height)
        guard size != frame.size else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }

    /// Поверх всех окон либо на столе: под обычными окнами, но над иконками.
    var onTop: Bool {
        get { level == .floating }
        set { level = newValue ? .floating : NSWindow.Level(NSWindow.Level.normal.rawValue - 1) }
    }
}
