import Foundation

enum InputEvent {
    case enter(side: Side, ratio: Double)
    case leave                               // controller pulled back (failsafe / disconnect)
    case handback(ratio: Double)
    case move(dx: Int, dy: Int)
    case mouseDown(button: Int)
    case mouseUp(button: Int)
    case scroll(dy: Int, dx: Int)
    case keyDown(code: Int)
    case keyUp(code: Int)
    case flags(UInt64)

    private enum Tag: UInt8 { case enter = 1, leave, handback, move, mDown, mUp, scroll, kDown, kUp, flags }

    func encode() -> Data {
        var d = Data()
        switch self {
        case let .enter(side, ratio):
            d.append(Tag.enter.rawValue); d.append(side.rawValue); d.appendF32(ratio)
        case .leave:
            d.append(Tag.leave.rawValue)
        case let .handback(ratio):
            d.append(Tag.handback.rawValue); d.appendF32(ratio)
        case let .move(dx, dy):
            d.append(Tag.move.rawValue); d.appendI16(dx); d.appendI16(dy)
        case let .mouseDown(b):
            d.append(Tag.mDown.rawValue); d.append(UInt8(clamping: b))
        case let .mouseUp(b):
            d.append(Tag.mUp.rawValue); d.append(UInt8(clamping: b))
        case let .scroll(dy, dx):
            d.append(Tag.scroll.rawValue); d.appendI16(dy); d.appendI16(dx)
        case let .keyDown(c):
            d.append(Tag.kDown.rawValue); d.appendU16(c)
        case let .keyUp(c):
            d.append(Tag.kUp.rawValue); d.appendU16(c)
        case let .flags(f):
            d.append(Tag.flags.rawValue); d.appendU64(f)
        }
        return d
    }

    init?(_ data: Data) {
        var r = ByteReader(data)
        guard let raw = r.u8(), let tag = Tag(rawValue: raw) else { return nil }
        switch tag {
        case .enter:
            guard let s = r.u8(), let side = Side(rawValue: s), let ratio = r.f32() else { return nil }
            self = .enter(side: side, ratio: ratio)
        case .leave:
            self = .leave
        case .handback:
            guard let ratio = r.f32() else { return nil }
            self = .handback(ratio: ratio)
        case .move:
            guard let dx = r.i16(), let dy = r.i16() else { return nil }
            self = .move(dx: dx, dy: dy)
        case .mDown:
            guard let b = r.u8() else { return nil }; self = .mouseDown(button: Int(b))
        case .mUp:
            guard let b = r.u8() else { return nil }; self = .mouseUp(button: Int(b))
        case .scroll:
            guard let dy = r.i16(), let dx = r.i16() else { return nil }
            self = .scroll(dy: dy, dx: dx)
        case .kDown:
            guard let c = r.u16() else { return nil }; self = .keyDown(code: Int(c))
        case .kUp:
            guard let c = r.u16() else { return nil }; self = .keyUp(code: Int(c))
        case .flags:
            guard let f = r.u64() else { return nil }; self = .flags(f)
        }
    }
}

private extension Data {
    mutating func appendI16(_ v: Int) { let u = UInt16(bitPattern: Int16(clamping: v)).bigEndian; Swift.withUnsafeBytes(of: u) { append(contentsOf: $0) } }
    mutating func appendU16(_ v: Int) { let u = UInt16(clamping: v).bigEndian; Swift.withUnsafeBytes(of: u) { append(contentsOf: $0) } }
    mutating func appendU64(_ v: UInt64) { let u = v.bigEndian; Swift.withUnsafeBytes(of: u) { append(contentsOf: $0) } }
    mutating func appendF32(_ v: Double) { let u = Float(v).bitPattern.bigEndian; Swift.withUnsafeBytes(of: u) { append(contentsOf: $0) } }
}

private struct ByteReader {
    let d: Data; var i: Int
    init(_ d: Data) { self.d = d; i = d.startIndex }
    mutating func u8() -> UInt8? { guard i < d.endIndex else { return nil }; defer { i += 1 }; return d[i] }
    mutating func u16() -> UInt16? { guard let hi = u8(), let lo = u8() else { return nil }; return UInt16(hi) << 8 | UInt16(lo) }
    mutating func i16() -> Int? { guard let v = u16() else { return nil }; return Int(Int16(bitPattern: v)) }
    mutating func u64() -> UInt64? { var v: UInt64 = 0; for _ in 0..<8 { guard let b = u8() else { return nil }; v = v << 8 | UInt64(b) }; return v }
    mutating func f32() -> Double? { guard let v = u32() else { return nil }; return Double(Float(bitPattern: v)) }
    mutating func u32() -> UInt32? { var v: UInt32 = 0; for _ in 0..<4 { guard let b = u8() else { return nil }; v = v << 8 | UInt32(b) }; return v }
}
