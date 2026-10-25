import CoreGraphics

// re-show local cursor on real input; host-hide must not strand it
final class LocalCursorGuard {
    var onLocalInput: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var active: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            bit(.mouseMoved) | bit(.leftMouseDown) | bit(.rightMouseDown) | bit(.otherMouseDown)
            | bit(.leftMouseDragged) | bit(.rightMouseDragged) | bit(.scrollWheel)
            | bit(.keyDown) | bit(.flagsChanged)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<LocalCursorGuard>.fromOpaque(info).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    me.reenable()
                } else if event.getIntegerValueField(.eventSourceUnixProcessID) == 0 {   // hardware, not injected
                    CursorHide.show()
                    me.onLocalInput?()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        source = src
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
    }

    private func reenable() { if let t = tap { CGEvent.tapEnable(tap: t, enable: true) } }
    private func bit(_ t: CGEventType) -> CGEventMask { CGEventMask(1) << t.rawValue }
}
