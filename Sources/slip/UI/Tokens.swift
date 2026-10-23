import SwiftUI

enum T {
    static let xs2: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let radius: CGFloat = 6
    static let panelWidth: CGFloat = 240

    static let tBody: CGFloat = 13
    static let tSmall: CGFloat = 11

    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }
}
