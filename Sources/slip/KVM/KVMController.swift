import CoreGraphics

final class KVMController {
    var onEvent: ((InputEvent) -> Void)?
    var onLocalInput: (() -> Void)?   // fired on local input while not remote

    private var side: Side
    private var align: Double
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var remote = false
    private var residualX = 0.0
    private var residualY = 0.0
    private var crossArmed = true   // edge hysteresis: must leave the edge before re-crossing
    private static let rearmMargin: CGFloat = 20
    // sustained push to cross, not a graze (so an autohide Dock at the edge can still reveal)
    private var pushSince: DispatchTime?
    private var lastPush: DispatchTime?
    private var pushTravel: CGFloat = 0
    private static let pushGap     = DispatchTimeInterval.milliseconds(90)
    private let crossHold: DispatchTimeInterval
    private let crossTravel: CGFloat
    private let crossBand: Double

    private static let escKey = 53
    private static let failsafe: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    private static let modMask: UInt64 = CGEventFlags([.maskAlphaShift, .maskShift, .maskControl,
        .maskAlternate, .maskCommand, .maskNumericPad, .maskHelp, .maskSecondaryFn]).rawValue

    init(side: Side, align: Double) {
        self.side = side; self.align = align
        crossHold = .milliseconds(Settings.crossHoldMs)
        crossTravel = CGFloat(Settings.crossTravelPx)
        crossBand = Double(Settings.crossBandPx)
    }
    func setArrange(side s: Side, align a: Double) { side = s; align = a }

    func start() -> Bool {
        let mask: CGEventMask =
            bit(.mouseMoved) | bit(.leftMouseDragged) | bit(.rightMouseDragged) | bit(.otherMouseDragged)
            | bit(.leftMouseDown) | bit(.leftMouseUp) | bit(.rightMouseDown) | bit(.rightMouseUp)
            | bit(.otherMouseDown) | bit(.otherMouseUp) | bit(.scrollWheel)
            | bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,   // HID layer: upstream of cursor render, so hide sticks (deskflow/input-leap)
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

    private func pushingOut(_ dx: Int, _ dy: Int) -> Bool {
        switch side {
        case .left:   return dx < 0
        case .right:  return dx > 0
        case .top:    return dy < 0
        case .bottom: return dy > 0
        }
    }

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
            onLocalInput?()   // host in local use -> active screen
            // no cross mid-drag (strands a held button)
            if type == .mouseMoved {
                let b = Geometry.desktopBounds()
                let loc = event.location
                let dx = Int(event.getDoubleValueField(.mouseEventDeltaX).rounded(.towardZero))
                let dy = Int(event.getDoubleValueField(.mouseEventDeltaY).rounded(.towardZero))
                if edgeDistance(loc, b) > Self.rearmMargin { crossArmed = true }
                let ratio = Geometry.crossingRatio(cursor: loc, side: side, margin: crossBand, b)
                let now = DispatchTime.now()
                if crossArmed, let ratio, pushingOut(dx, dy) {
                    if let last = lastPush, now > last + Self.pushGap { pushSince = nil; pushTravel = 0 }   // gap breaks the gesture
                    if pushSince == nil { pushSince = now }
                    lastPush = now
                    pushTravel += CGFloat(abs((side == .left || side == .right) ? dx : dy))
                    if now >= pushSince! + crossHold, pushTravel >= crossTravel {
                        enterRemote(ratio: ratio, flags: event.flags.rawValue & Self.modMask, from: loc)
                        crossArmed = false
                        pushSince = nil; lastPush = nil; pushTravel = 0
                        return nil
                    }
                } else {
                    pushSince = nil; lastPush = nil; pushTravel = 0
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

    private func enterRemote(ratio: Double, flags: UInt64, from: CGPoint) {
        remote = true
        residualX = 0; residualY = 0
        let b = Geometry.desktopBounds()
        CGWarpMouseCursorPosition(CGPoint(x: b.minX - 100, y: b.minY - 100))   // park off all displays: a hardware sprite that hide can't clear stays off-screen
        let hideErr = CursorHide.hide()
        CGAssociateMouseAndMouseCursorPosition(0)   // detach last; raw deltas
        let r = min(1, max(0, ratio - align))
        Log.line("ctrl cross-out side=\(side.opposite) ratio=\(String(format: "%.2f", r)) from=\(Int(from.x)),\(Int(from.y)) onMain=\(Geometry.mainBounds().contains(from)) hide=\(hideErr.rawValue)")
        onEvent?(.enter(side: side.opposite, ratio: r))
        onEvent?(.flags(flags))   // carry held modifiers across
    }

    private func leaveRemote(warpTo: CGPoint?, tellReceiver: Bool) {
        remote = false
        crossArmed = false   // landed near the edge; require moving away before re-crossing
        CGAssociateMouseAndMouseCursorPosition(1)   // reattach
        CursorHide.show()                            // show before warp (warp while hidden leaves a frozen ghost)
        if let p = warpTo { CGWarpMouseCursorPosition(p) }
        if tellReceiver { onEvent?(.leave) }
    }

    private func bit(_ t: CGEventType) -> CGEventMask { CGEventMask(1) << t.rawValue }
}
