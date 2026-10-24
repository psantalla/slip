import CoreGraphics

// private CGS: lets CGDisplayHideCursor work from a background (accessory) app.
// bound at load; if a future macOS drops them the app won't launch.
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ owner: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

// deskflow/input-leap recipe: re-assert the property before EVERY hide, keep the
// hide count at exactly 1 via a bool, end each call with associate(true) so the hide registers.
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
        let e = CGDisplayHideCursor(CGMainDisplayID())    // only covers the display the cursor is on; caller warps to main first (multi-monitor)
        CGAssociateMouseAndMouseCursorPosition(1)         // kick so the hide actually registers
        hidden = true
        return e
    }

    static func show() {
        guard hidden else { return }
        allowInBackground()
        CGDisplayShowCursor(CGMainDisplayID())
        CGAssociateMouseAndMouseCursorPosition(1)
        hidden = false
    }
}
