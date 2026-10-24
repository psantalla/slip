import SwiftUI

enum T {
    static let xs2: CGFloat = 3
    static let xs: CGFloat = 6
    static let s: CGFloat = 10
    static let m: CGFloat = 12
    static let radius: CGFloat = 6
    static let panelRadius: CGFloat = 10
    static let panelWidth: CGFloat = 252

    static let tBody: CGFloat = 13

    static func font(_ size: CGFloat, medium: Bool = false) -> Font {
        .system(size: size, weight: medium ? .medium : .regular)
    }
}
