import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let core = Core()
    private var statusItem: NSStatusItem!
    private var window: DropWindow!
    private var hosting: NSHostingView<Panel>!
    private var outsideClick: Any?
    private var closedAt = Date.distantPast
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        let stamp = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        Log.line("launch stamp=\(stamp) role=\(core.role.rawValue) ax=\(Permissions.accessibility) im=\(Permissions.inputMonitoring)")
        core.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        hosting = NSHostingView(rootView: Panel(core: core))
        window = DropWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.contentView = hosting
        window.delegate = self

        Publishers.CombineLatest(core.$status, core.$role).sink { [weak self] status, role in
            let connected: Bool = { if case .connected = status { return true }; return false }()
            self?.setIcon(host: role == .host, connected: connected)
        }.store(in: &bag)

        core.objectWillChange.sink { [weak self] in   // re-fit while open: role/toggles change height
            guard self?.window.isVisible == true else { return }
            DispatchQueue.main.async { self?.refit() }
        }.store(in: &bag)

        registerLoginItem()
    }

    // start at login, so it returns to the menu bar after a reboot
    private func registerLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        let svc = SMAppService.mainApp
        guard svc.status != .enabled else { return }
        do { try svc.register() } catch { Log.line("login item register failed: \(error)") }
    }

    @objc private func toggle() {
        if window.isVisible { hide(); return }
        if Date().timeIntervalSince(closedAt) < 0.2 { return }   // swallow resignKey->reopen on self-click
        show()
    }

    private func show() {
        guard statusItem.button?.window != nil else { return }
        layoutWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    // size to content + anchor under the status item; also on content change while open
    private func layoutWindow() {
        guard let button = statusItem.button, let bw = button.window else { return }
        window.setContentSize(hosting.fittingSize)
        let anchor = bw.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(x: anchor.midX - window.frame.width / 2, y: anchor.minY - 6 - window.frame.height)
        if let vis = bw.screen?.visibleFrame {
            origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - window.frame.width - 8)
        }
        window.setFrameOrigin(origin)
        window.invalidateShadow()
    }

    private func refit() { if window.isVisible { layoutWindow() } }

    private func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        closedAt = Date()
        if let m = outsideClick { NSEvent.removeMonitor(m); outsideClick = nil }
    }

    func windowDidResignKey(_ note: Notification) { hide() }

    private func setIcon(host: Bool, connected: Bool) {
        statusItem.button?.image = Self.icon(host: host, connected: connected)
        statusItem.button?.setAccessibilityLabel("Slip, \(host ? "host" : "join"), \(connected ? "linked" : "not linked")")
    }

    // filled = host, ring = join; peer dims until linked, fuses when linked
    private static func icon(host: Bool, connected: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            let r: CGFloat = 2.8
            let a = NSPoint(x: 5.1, y: 5.3), b = NSPoint(x: 9.5, y: 8.9)
            func vec(_ o: NSPoint, _ ang: CGFloat, _ l: CGFloat) -> NSPoint { NSPoint(x: o.x + cos(ang) * l, y: o.y + sin(ang) * l) }
            func oval(_ c: NSPoint) -> NSRect { NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
            // metaball bridge between the two drops (Vachhar connector)
            func neck() -> NSBezierPath {
                let hp = CGFloat.pi / 2, pi = CGFloat.pi
                let d = hypot(b.x - a.x, b.y - a.y), ab = atan2(b.y - a.y, b.x - a.x)
                let u = d < 2 * r ? acos(d / (2 * r)) : 0
                let v: CGFloat = 0.34, hr: CGFloat = 3.1
                let a1 = ab + u + (hp - u) * v, a2 = ab - u - (hp - u) * v
                let a3 = ab + pi - u - (pi - u - hp) * v, a4 = ab - pi + u + (pi - u - hp) * v
                let p1 = vec(a, a1, r), p2 = vec(a, a2, r), p3 = vec(b, a3, r), p4 = vec(b, a4, r)
                let h = r * min(v * hr, hypot(p1.x - p3.x, p1.y - p3.y) / (2 * r))
                let p = NSBezierPath(); p.move(to: p1)
                p.curve(to: p3, controlPoint1: vec(p1, a1 - hp, h), controlPoint2: vec(p3, a3 + hp, h))
                p.line(to: p4)
                p.curve(to: p2, controlPoint1: vec(p4, a4 - hp, h), controlPoint2: vec(p2, a2 + hp, h))
                p.close(); return p
            }
            NSColor.black.withAlphaComponent(connected ? 1 : 0.5).setFill()
            NSBezierPath(ovalIn: oval(b)).fill()
            NSColor.black.setFill(); NSColor.black.setStroke()
            if host {
                NSBezierPath(ovalIn: oval(a)).fill()
            } else {
                let p = NSBezierPath(ovalIn: oval(a).insetBy(dx: 0.7, dy: 0.7)); p.lineWidth = 1.4; p.stroke()
            }
            if connected { neck().fill() }
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class DropWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
