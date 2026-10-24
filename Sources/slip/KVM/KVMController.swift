import CoreGraphics

final class KVMController {
    var onEvent: ((InputEvent) -> Void)?

    private var side: Side
    private var align: Double
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var remote = false
    private var residualX = 0.0
    private var residualY = 0.0
    private var crossArmed = true   // edge hysteresis: must leave the edge before re-crossing
    private static let rearmMargin: CGFloat = 20

    private static let escKey = 53
    private static let failsafe: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    private static let modMask: UInt64 = CGEventFlags([.maskAlphaShift, .maskShift, .maskControl,
        .maskAlternate, .maskCommand, .maskNumericPad, .maskHelp, .maskSecondaryFn]).rawValue

    init(side: Side, align: Double) { self.side = side; self.align = align }
    func setArrange(side s: Side, align a: Double) { side = s; align = a }

    func start() -> Bool {
        let mask: CGEventMask =
            bit(.mouseMoved) | bit(.leftMouseDragged) | bit(.rightMouseDragged) | bit(.otherMouseDragged)
            | bit(.leftMouseDown) | bit(.leftMouseUp) | bit(.rightMouseDown) | bit(.rightMouseUp)
            | bit(.otherMouseDown) | bit(.otherMouseUp) | bit(.scrollWheel)
            | bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                let me = Unmanaged<KVMController>.fromOpaque(info!).takeUnretainedValue()
                return me.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        source = src
        return true
    }

    func stop() {
        if remote { leaveRemote(warpTo: nil, tellReceiver: true) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil; source = nil
    }

    // re-enable a silently disabled tap
    func ensureEnabled() {
        if let t = tap, !CGEvent.tapIsEnabled(tap: t) { CGEvent.tapEnable(tap: t, enable: true) }
    }

    // keep the local cursor frozen if the OS re-linked it while controlling
    func reassert() { if remote { CGAssociateMouseAndMouseCursorPosition(0) } }

    private func edgeDistance(_ p: CGPoint, _ b: CGRect) -> CGFloat {
        switch side {
        case .left:   return p.x - b.minX
        case .right:  return b.maxX - p.x
        case .top:    return p.y - b.minY
        case .bottom: return b.maxY - p.y
        }
    }

    func handback(ratio: Double) {
        guard remote else { return }
        let r = min(1, max(0, ratio + align))
        let p = Geometry.clamp(Geometry.reentryPoint(side: side, ratio: r, Geometry.desktopBounds()), to: Geometry.activeDisplayRects())
        leaveRemote(warpTo: p, tellReceiver: false)   // keep reentry on a real display (offset multi-monitor dead zones)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // failsafe: always return to local, no matter the state
        if type == .keyDown, Int(event.getIntegerValueField(.keyboardEventKeycode)) == Self.escKey,
           event.flags.isSuperset(of: Self.failsafe) {
            if remote {
                let b = Geometry.mainBounds()
                leaveRemote(warpTo: CGPoint(x: b.midX, y: b.midY), tellReceiver: true)   // center, not the edge
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if !remote {
            // no cross mid-drag (strands a held button)
            if type == .mouseMoved {
                let b = Geometry.desktopBounds()
                if edgeDistance(event.location, b) > Self.rearmMargin { crossArmed = true }
                if crossArmed, let ratio = Geometry.crossingRatio(cursor: event.location, side: side, b) {
                    enterRemote(ratio: ratio, flags: event.flags.rawValue & Self.modMask)
                    crossArmed = false
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        CGAssociateMouseAndMouseCursorPosition(0)   // keep the local cursor frozen, re-assert each event

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let rx = event.getDoubleValueField(.mouseEventDeltaX) + residualX
            let ry = event.getDoubleValueField(.mouseEventDeltaY) + residualY
            let dx = Int(rx.rounded(.towardZero))
            let dy = Int(ry.rounded(.towardZero))
            residualX = rx - Double(dx)
            residualY = ry - Double(dy)
            if dx != 0 || dy != 0 { onEvent?(.move(dx: dx, dy: dy)) }
        case .leftMouseDown:  onEvent?(.mouseDown(button: 0))
        case .leftMouseUp:    onEvent?(.mouseUp(button: 0))
        case .rightMouseDown: onEvent?(.mouseDown(button: 1))
        case .rightMouseUp:   onEvent?(.mouseUp(button: 1))
        case .otherMouseDown: onEvent?(.mouseDown(button: Int(event.getIntegerValueField(.mouseEventButtonNumber))))
        case .otherMouseUp:   onEvent?(.mouseUp(button: Int(event.getIntegerValueField(.mouseEventButtonNumber))))
        case .scrollWheel:
            onEvent?(.scroll(dy: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                             dx: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))))
        case .keyDown: onEvent?(.keyDown(code: Int(event.getIntegerValueField(.keyboardEventKeycode))))
        case .keyUp:   onEvent?(.keyUp(code: Int(event.getIntegerValueField(.keyboardEventKeycode))))
        case .flagsChanged: onEvent?(.flags(event.flags.rawValue & Self.modMask))
        default: break
        }
        return nil
    }

    private func enterRemote(ratio: Double, flags: UInt64) {
        remote = true
        residualX = 0; residualY = 0
        let main = Geometry.mainBounds()
        CGWarpMouseCursorPosition(CGPoint(x: main.midX, y: main.midY))   // cursor onto the display we hide; else it strands on a 2nd monitor (deskflow #10225)
        let hideErr = CursorHide.hide()             // hide BEFORE detach so it registers (ends with associate(true))
        CGAssociateMouseAndMouseCursorPosition(0)   // then detach; raw deltas, so the warp doesn't pollute motion
        let r = min(1, max(0, ratio - align))
        Log.line("ctrl cross-out side=\(side.opposite) ratio=\(String(format: "%.2f", r)) hide=\(hideErr.rawValue)")
        onEvent?(.enter(side: side.opposite, ratio: r))
        onEvent?(.flags(flags))   // carry held modifiers across
    }

    private func leaveRemote(warpTo: CGPoint?, tellReceiver: Bool) {
        remote = false
        crossArmed = false   // landed near the edge; require moving away before re-crossing
        CGAssociateMouseAndMouseCursorPosition(1)   // reattach FIRST
        if let p = warpTo { CGWarpMouseCursorPosition(p) }
        CursorHide.show()
        if tellReceiver { onEvent?(.leave) }
    }

    private func bit(_ t: CGEventType) -> CGEventMask { CGEventMask(1) << t.rawValue }
}
