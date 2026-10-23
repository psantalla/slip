import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let core = Core()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        let stamp = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        Log.line("launch stamp=\(stamp) role=\(core.role.rawValue) ax=\(Permissions.accessibility) im=\(Permissions.inputMonitoring)")
        core.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Panel(core: core))

        Publishers.CombineLatest(core.$status, core.$role).sink { [weak self] status, role in
            let connected: Bool = { if case .connected = status { return true }; return false }()
            self?.setIcon(host: role == .host, connected: connected)
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
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()   // let text fields take keyboard input
        }
    }

    private func setIcon(host: Bool, connected: Bool) {
        statusItem.button?.image = Self.icon(host: host, connected: connected)
        statusItem.button?.setAccessibilityLabel("Slip, \(host ? "host" : "client"), \(connected ? "linked" : "not linked")")
    }

    // this Mac's droplet: filled = host, ring = client. Peer droplet dims until linked.
    private static func icon(host: Bool, connected: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            let r: CGFloat = 3.4, cr: CGFloat = 1.5
            func cell(_ cx: CGFloat, _ cy: CGFloat, filled: Bool, _ alpha: CGFloat) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSColor.black.withAlphaComponent(alpha).setStroke()
                if filled {
                    NSBezierPath(roundedRect: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r),
                                 xRadius: cr, yRadius: cr).fill()
                } else {
                    let p = NSBezierPath(roundedRect: NSRect(x: cx - r + 0.7, y: cy - r + 0.7, width: 2 * r - 1.4, height: 2 * r - 1.4),
                                         xRadius: cr, yRadius: cr)
                    p.lineWidth = 1.4; p.stroke()
                }
            }
            cell(5.6, 6.0, filled: host, 1)
            cell(9.0, 8.4, filled: true, connected ? 1 : 0.5)
            return true
        }
        image.isTemplate = true
        return image
    }
}
