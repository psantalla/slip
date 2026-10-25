import CoreGraphics

// private CGS; missing symbol = won't launch
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ owner: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

// re-assert each hide; bool keeps CG hide-count at 1
enum CursorHide {
    private static var hidden = false

    private static func allowInBackground() {
        let cid = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    @discardableResult
    static func hide() -> CGError {
        guard !hidden else { return .success }
        allowInBackground()
        var err: CGError = .success
        for id in activeDisplays() where CGDisplayHideCursor(id) != .success { err = .failure }   // every display; main-only misses a secondary
        CGAssociateMouseAndMouseCursorPosition(1)
        hidden = true
        return err
    }

    static func show() {
        guard hidden else { return }
        allowInBackground()
        for id in activeDisplays() { CGDisplayShowCursor(id) }
        CGAssociateMouseAndMouseCursorPosition(1)
        hidden = false
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [CGMainDisplayID()] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids
    }
}
