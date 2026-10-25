import SwiftUI

struct Panel: View {
    @ObservedObject var core: Core

    var body: some View {
        VStack(alignment: .leading, spacing: T.m) {
            roles
            if core.isConnected {
                linkedBody
                shareSection
            } else {
                pairing
            }
            footer.padding(.top, T.xs)
        }
        .padding(T.m)
        .frame(width: T.panelWidth)
        .font(T.font(T.tBody))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: T.panelRadius))
    }

    private var codeReady: Bool {
        Wire.normalizeCode(core.joinCode).count >= 8
    }

    private var roles: some View {
        HStack(spacing: T.m) {
            roleSeg("Host", .host)
            roleSeg("Join", .join)
        }
    }

    private func roleSeg(_ title: String, _ r: Role) -> some View {
        let active = core.role == r
        return Button { core.setRole(r) } label: {
            Text(title).font(T.font(T.tBody)).foregroundStyle(.primary)
        }
        .buttonStyle(.plain).focusEffectDisabled().hover(active: active)
        .disabled(core.isConnected)   // disconnect first to switch role
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    @ViewBuilder private var pairing: some View {
        switch core.role {
        case .host:
            HStack(alignment: .firstTextBaseline) {
                Text(core.code).tracking(1).textSelection(.enabled)
                    .lineLimit(1).fixedSize()
                    .accessibilityLabel(core.code.map(String.init).joined(separator: " "))
                Spacer()
                link("New code") { core.regenerateCode() }
            }
            .padding(.vertical, T.xs).padding(.horizontal, T.s)
            .background(RoundedRectangle(cornerRadius: T.radius).fill(.primary.opacity(0.06)))
        case .join:
            VStack(alignment: .leading, spacing: T.xs) {
                HStack(alignment: .firstTextBaseline) {
                    TextField("Host code", text: $core.joinCode)
                        .textFieldStyle(.plain)
                        .onSubmit { core.connect() }
                    link("Connect") { core.connect() }
                }
                .padding(.vertical, T.xs).padding(.horizontal, T.s)
                .background(RoundedRectangle(cornerRadius: T.radius).fill(.primary.opacity(0.06)))
                joinStatus
            }
        }
    }

    @ViewBuilder private var joinStatus: some View {
        if core.status == .connecting {
            meta("Connecting\u{2026}", say: "Connecting")
        } else if core.status == .failed {
            meta("Couldn't connect")
        } else if !codeReady {
            meta("Enter the code")
        }
    }

    private var linkedBody: some View {
        VStack(alignment: .leading, spacing: T.xs) {
            Text("Connected to \(core.peerName ?? "the other Mac")")
                .lineLimit(1).truncationMode(.tail)
            link("Disconnect") { core.disconnect() }
        }
    }

    @ViewBuilder private var shareSection: some View {
        VStack(alignment: .leading, spacing: T.xs) {
            meta("Share")
            if core.role == .host {
                toggle("Keyboard & mouse", core.kvmOn) { core.setKVM($0) }
            }
            toggle("Clipboard", core.clipOn) { core.setClip($0) }
            toggle("Files", core.clipOn && core.filesOn) { core.setFiles($0) }
                .disabled(!core.clipOn)   // files ride the clipboard
            if core.role == .host, core.kvmOn { hostKVMDetail }   // layout last, after the 3 toggles
            if core.role == .join { receiverKVM }
        }
    }

    @ViewBuilder private var hostKVMDetail: some View {
        meta("Screen layout").padding(.top, T.xs2)
        ArrangeView(core: core)
        if !Permissions.accessibility {
            perm("Accessibility", false) { Permissions.requestAccessibility(); Permissions.openAccessibility() }
        }
        if !Permissions.inputMonitoring {
            perm("Input Monitoring", false) { Permissions.requestInputMonitoring(); Permissions.openInputMonitoring() }
        }
    }

    @ViewBuilder private var receiverKVM: some View {
        if !Permissions.accessibility {
            perm("Accessibility", false) { Permissions.requestAccessibility(); Permissions.openAccessibility() }
        }
    }

    private static let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"

    private var footer: some View {
        HStack {
            meta(Self.build, say: "Build \(Self.build)")
            Spacer()
            link("Quit") { NSApp.terminate(nil) }
        }
    }

    private func toggle(_ title: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { on }, set: set))
            .toggleStyle(.switch).controlSize(.mini).font(T.font(T.tBody))
    }

    private func meta(_ text: String, say: String? = nil) -> some View {
        Text(text).font(T.font(T.tBody)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(say ?? text)
    }

    private func link(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(T.font(T.tBody)).foregroundStyle(.primary)
                .lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain).hover()
    }

    private func perm(_ name: String, _ granted: Bool, _ action: @escaping () -> Void) -> some View {
        link("\(name) (\(granted ? "granted" : "needed"))", action)
    }

}

private struct ArrangeView: View {
    @ObservedObject var core: Core
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tileH: CGFloat = 40
    private let gap: CGFloat = 10
    private var alignRange: CGFloat { tileH }   // slide the other screen this far along the edge

    private var tileW: CGFloat {   // capped so the 3-tile span fits the 208pt content width
        let b = Geometry.mainBounds()
        return min(60, max(48, tileH * (b.width / max(1, b.height))))
    }

    var body: some View {
        let resting = restingOffset(core.kvmSide, core.kvmAlign)
        ZStack {
            tile("Host", strong: false, offset: .zero)
            tile("Join", strong: true,
                 offset: CGSize(width: resting.width + drag.width, height: resting.height + drag.height))
                .zIndex(1)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { v in
                            let p = CGSize(width: resting.width + v.translation.width,
                                           height: resting.height + v.translation.height)
                            let (side, align) = arrangement(p)
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                drag = .zero
                                core.setArrange(side: side, align: align)
                            }
                        }
                )
                .accessibilityLabel("Other Mac, \(name(core.kvmSide)). Drag to move.")
        }
        .frame(width: (tileW + gap) * 2 + tileW, height: (tileH + gap) * 2 + tileH)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ label: String, strong: Bool, offset: CGSize) -> some View {
        Text(label).font(T.font(T.tBody)).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.tail).padding(.horizontal, 3)
            .frame(width: tileW, height: tileH)
            .background(RoundedRectangle(cornerRadius: T.radius).fill(.primary.opacity(strong ? 0.16 : 0.08)))
            .offset(x: offset.width, y: offset.height)
    }

    private func restingOffset(_ s: Side, _ a: Double) -> CGSize {
        let off = CGFloat(a) * alignRange
        switch s {
        case .right:  return CGSize(width: tileW + gap, height: off)
        case .left:   return CGSize(width: -(tileW + gap), height: off)
        case .bottom: return CGSize(width: off, height: tileH + gap)
        case .top:    return CGSize(width: off, height: -(tileH + gap))
        }
    }

    private func arrangement(_ p: CGSize) -> (Side, Double) {
        let side: Side = abs(p.width) >= abs(p.height)
            ? (p.width >= 0 ? .right : .left) : (p.height >= 0 ? .bottom : .top)
        let perp = (side == .left || side == .right) ? p.height : p.width
        let a = max(-1, min(1, Double(perp / alignRange)))
        return (side, (a / 0.25).rounded() * 0.25)   // snap to steps, not hypersensitive
    }

    private func name(_ s: Side) -> String {
        switch s { case .left: "left"; case .right: "right"; case .top: "top"; case .bottom: "bottom" }
    }
}

// selection by opacity, no box/halo
private struct HoverOpacity: ViewModifier {
    let active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(active || on ? 1 : 0.5).onHover { on = $0 }
    }
}

private extension View {
    func hover(active: Bool = false) -> some View { modifier(HoverOpacity(active: active)) }
}
