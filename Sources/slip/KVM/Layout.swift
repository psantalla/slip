import CoreGraphics

enum Side: UInt8 {
    case left = 0, right, top, bottom
    var opposite: Side { switch self { case .left: .right; case .right: .left; case .top: .bottom; case .bottom: .top } }
}

enum Geometry {
    static func mainBounds() -> CGRect { CGDisplayBounds(CGMainDisplayID()) }

    static func activeDisplayRects() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [mainBounds()] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map { CGDisplayBounds($0) }
    }

    // union of all displays, so an injected cursor can roam every monitor on the receiver
    static func union(_ rects: [CGRect]) -> CGRect {
        let r = rects.reduce(CGRect.null) { $0.union($1) }
        return r.isNull ? mainBounds() : r
    }

    static func desktopBounds() -> CGRect { union(activeDisplayRects()) }

    // keep a point on a real display; offset layouts leave dead zones in the union bbox
    static func clamp(_ p: CGPoint, to rects: [CGRect]) -> CGPoint {
        if rects.contains(where: { $0.contains(p) }) { return p }
        var best = p, bestD = CGFloat.greatestFiniteMagnitude
        for r in rects {
            let x = min(max(p.x, r.minX), r.maxX - 1)
            let y = min(max(p.y, r.minY), r.maxY - 1)
            let d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
            if d < bestD { bestD = d; best = CGPoint(x: x, y: y) }
        }
        return best
    }

    static func crossingRatio(cursor: CGPoint, side: Side, _ b: CGRect) -> Double? {
        let m = 1.0
        switch side {
        case .right:  return cursor.x >= b.maxX - m ? clamp((cursor.y - b.minY) / b.height) : nil
        case .left:   return cursor.x <= b.minX + m ? clamp((cursor.y - b.minY) / b.height) : nil
        case .bottom: return cursor.y >= b.maxY - m ? clamp((cursor.x - b.minX) / b.width) : nil
        case .top:    return cursor.y <= b.minY + m ? clamp((cursor.x - b.minX) / b.width) : nil
        }
    }

    static func entryPoint(side: Side, ratio: Double, _ b: CGRect) -> CGPoint {
        switch side {
        case .left:   return CGPoint(x: b.minX + 1,          y: b.minY + ratio * b.height)
        case .right:  return CGPoint(x: b.maxX - 1,          y: b.minY + ratio * b.height)
        case .top:    return CGPoint(x: b.minX + ratio * b.width, y: b.minY + 1)
        case .bottom: return CGPoint(x: b.minX + ratio * b.width, y: b.maxY - 1)
        }
    }

    static func exitRatio(cursor: CGPoint, side: Side, _ b: CGRect) -> Double? {
        switch side {
        case .left:   return cursor.x <= b.minX ? clamp((cursor.y - b.minY) / b.height) : nil
        case .right:  return cursor.x >= b.maxX - 1 ? clamp((cursor.y - b.minY) / b.height) : nil
        case .top:    return cursor.y <= b.minY ? clamp((cursor.x - b.minX) / b.width) : nil
        case .bottom: return cursor.y >= b.maxY - 1 ? clamp((cursor.x - b.minX) / b.width) : nil
        }
    }

    static func reentryPoint(side: Side, ratio: Double, _ b: CGRect) -> CGPoint {
        switch side {
        case .right:  return CGPoint(x: b.maxX - 3,          y: b.minY + ratio * b.height)
        case .left:   return CGPoint(x: b.minX + 3,          y: b.minY + ratio * b.height)
        case .bottom: return CGPoint(x: b.minX + ratio * b.width, y: b.maxY - 3)
        case .top:    return CGPoint(x: b.minX + ratio * b.width, y: b.minY + 3)
        }
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}
