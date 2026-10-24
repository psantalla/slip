import CoreGraphics

final class KVMReceiver {
    var onHandback: ((Double) -> Void)?
    private(set) var active = false

    private let src = CGEventSource(stateID: .hidSystemState)
    private var pos = CGPoint.zero        // logical, in the union space (for edge detection)
    private var dispRects: [CGRect] = []
    private var flags: CGEventFlags = []
    private var buttons = Set<Int>()
    private var keysDown = Set<Int>()
    private var entrySide: Side = .left
    private var armed = false
    private var enteredAt = DispatchTime.now()
    private var pushSince: DispatchTime?
    private var lastPush: DispatchTime?
    private var pushTravel: CGFloat = 0
    private static let armDistance: CGFloat = 24
    private static let enterCooldown = DispatchTimeInterval.milliseconds(400)   // no handback right after crossing in
    private static let handbackHold  = DispatchTimeInterval.milliseconds(250)   // sustain the push this long
    private static let pushGap       = DispatchTimeInterval.milliseconds(90)    // a gap in pushing breaks continuity
    private static let handbackTravel: CGFloat = 45                             // px of attempted outward push needed
    private static let modKeys: [(CGEventFlags, Int)] = [
        (.maskShift, 56), (.maskControl, 59), (.maskAlternate, 58),
        (.maskCommand, 55), (.maskAlphaShift, 57), (.maskSecondaryFn, 63),
    ]

    func stop() {
        releaseHeld()
        active = false; armed = false; pushSince = nil; lastPush = nil; pushTravel = 0; flags = []
    }

    func handle(_ e: InputEvent) {
        switch e {
        case let .enter(side, ratio):
            releaseHeld()   // drop anything stuck from a prior session
            dispRects = Geometry.activeDisplayRects()
            let b = Geometry.union(dispRects)
            entrySide = side
            pos = Geometry.entryPoint(side: side, ratio: ratio, b)
            flags = []
            active = true; armed = false; enteredAt = .now(); pushSince = nil; lastPush = nil; pushTravel = 0
            Log.line("recv cross-in ax=\(Permissions.accessibility) pos=\(Int(pos.x)),\(Int(pos.y))")
            CGWarpMouseCursorPosition(inject())
            post(.mouseMoved, button: 0)
        case .leave, .handback:
            stop()
        case let .move(dx, dy):
            guard active else { return }
            dispRects = Geometry.activeDisplayRects()
            let b = Geometry.union(dispRects)
            pos.x = min(b.maxX - 1, max(b.minX, pos.x + CGFloat(dx)))
            pos.y = min(b.maxY - 1, max(b.minY, pos.y + CGFloat(dy)))
            let dist = inside(pos, b)
            if dist > Self.armDistance { armed = true }
            // hand back only on a sustained, deliberate push into the exit edge: not a graze, not right after entering
            let now = DispatchTime.now()
            if armed, now >= enteredAt + Self.enterCooldown, buttons.isEmpty, pushingOut(dx, dy),
               let ratio = Geometry.exitRatio(cursor: pos, side: entrySide, b) {
                if let last = lastPush, now > last + Self.pushGap { pushSince = nil; pushTravel = 0 }   // gap: restart the gesture
                if pushSince == nil { pushSince = now }
                lastPush = now
                pushTravel += CGFloat(abs((entrySide == .left || entrySide == .right) ? dx : dy))
                if now >= pushSince! + Self.handbackHold, pushTravel >= Self.handbackTravel {
                    Log.line("recv handback ratio=\(String(format: "%.2f", ratio))")
                    let cb = onHandback; stop(); cb?(ratio)
                    return
                }
            } else if isInward(dx, dy) {
                pushSince = nil; lastPush = nil; pushTravel = 0
            }
            post(dragType(), button: heldButton())
        case let .mouseDown(btn):
            guard active else { return }
            buttons.insert(btn); post(downType(btn), button: btn)
        case let .mouseUp(btn):
            guard active else { return }
            buttons.remove(btn); post(upType(btn), button: btn)
        case let .scroll(dy, dx):
            guard active else { return }
            let s = CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 2,
                            wheel1: Int32(clamping: dy), wheel2: Int32(clamping: dx), wheel3: 0)
            s?.flags = flags; s?.post(tap: .cghidEventTap)
        case let .keyDown(code):
            guard active else { return }
            keysDown.insert(code); key(code, down: true)
        case let .keyUp(code):
            guard active else { return }
            keysDown.remove(code); key(code, down: false)
        case let .flags(f):
            flags = CGEventFlags(rawValue: f)
        }
    }

    // keep the injected cursor on a real display; the union bbox can have dead zones
    private func inject() -> CGPoint { Geometry.clamp(pos, to: dispRects) }

    private func post(_ type: CGEventType, button: Int) {
        guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                              mouseCursorPosition: inject(), mouseButton: cgButton(button)) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    private func key(_ code: Int, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    private func releaseHeld() {
        for b in buttons { post(upType(b), button: b) }
        buttons.removeAll()
        for k in keysDown { key(k, down: false) }
        keysDown.removeAll()
        for (flag, code) in Self.modKeys where flags.contains(flag) {   // unlatch held modifiers on the Join
            CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    private func heldButton() -> Int { buttons.first ?? 0 }
    private func dragType() -> CGEventType {
        guard let b = buttons.first else { return .mouseMoved }
        return b == 0 ? .leftMouseDragged : b == 1 ? .rightMouseDragged : .otherMouseDragged
    }
    private func downType(_ b: Int) -> CGEventType { b == 0 ? .leftMouseDown : b == 1 ? .rightMouseDown : .otherMouseDown }
    private func upType(_ b: Int) -> CGEventType { b == 0 ? .leftMouseUp : b == 1 ? .rightMouseUp : .otherMouseUp }
    private func cgButton(_ b: Int) -> CGMouseButton {
        b == 0 ? .left : b == 1 ? .right : (CGMouseButton(rawValue: UInt32(b)) ?? .center)
    }

    private func pushingOut(_ dx: Int, _ dy: Int) -> Bool {
        switch entrySide {
        case .left:   return dx < 0
        case .right:  return dx > 0
        case .top:    return dy < 0
        case .bottom: return dy > 0
        }
    }

    private func isInward(_ dx: Int, _ dy: Int) -> Bool {
        switch entrySide {
        case .left:   return dx > 0
        case .right:  return dx < 0
        case .top:    return dy > 0
        case .bottom: return dy < 0
        }
    }

    private func inside(_ p: CGPoint, _ b: CGRect) -> CGFloat {
        switch entrySide {
        case .left:   return p.x - b.minX
        case .right:  return b.maxX - p.x
        case .top:    return p.y - b.minY
        case .bottom: return b.maxY - p.y
        }
    }
}
