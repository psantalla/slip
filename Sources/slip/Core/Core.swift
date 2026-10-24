import SwiftUI

@MainActor
final class Core: ObservableObject {
    @Published var role: Role
    @Published var code: String
    @Published var joinCode = Settings.joinCode
    @Published var status: LinkStatus = .disconnected

    @Published var clipOn = Settings.clipOn
    @Published var filesOn = Settings.filesOn
    @Published var kvmOn = Settings.kvmOn
    @Published var kvmSide = Settings.otherSide
    @Published var kvmAlign = Settings.kvmAlign

    var isConnected: Bool { if case .connected = status { return true }; return false }
    var peerName: String? { if case .connected(let p) = status { return p }; return nil }

    private let link: Link
    private let clip = Clipboard()
    private var kvm: KVM!
    private var saveDir: URL { Settings.saveDir }

    init() {
        let c = Settings.code
        code = c
        role = Role(rawValue: Settings.role) ?? .host
        link = Link(hostCode: c)

        clip.onLocal = { [weak self] h, d in
            guard let self, self.isConnected, self.clipOn, d.count <= Wire.maxPayload else { return }
            self.link.send(h, d)
        }
        clip.onLocalFiles = { [weak self] urls in self?.sendFiles(urls) }

        kvm = KVM(send: { [weak self] e in
            self?.link.send(Header(kind: Kind.input, name: nil, device: nil), e.encode())
        })
        kvm.setRole(role)

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.kvm.recheck()
                self.objectWillChange.send()
            }
        }

        link.onFrame = { [weak self] h, d in
            guard let self else { return }
            if h.kind == Kind.input {
                if let e = InputEvent(d) { self.kvm.receive(e) }
            } else if h.kind == Kind.file {
                guard self.clipOn, self.filesOn else { return }   // files ride the clipboard
                self.clip.apply(h, d, saveDir: self.saveDir)
            } else {
                guard self.clipOn else { return }
                self.clip.apply(h, d, saveDir: self.saveDir)
            }
        }
        link.onStatus = { [weak self] status in
            guard let self else { return }
            self.status = status
            let on = self.isConnected
            if on { self.clip.start() } else { self.clip.stop() }
            self.kvm.setConnected(on)
        }
    }

    func start() { apply(role) }

    func setRole(_ r: Role) {
        role = r
        Settings.role = r.rawValue
        kvm.setRole(r)
        status = .disconnected
        apply(r)
    }

    func disconnect() {
        status = .disconnected
        kvm.setConnected(false)
        apply(role)   // tear down the link, keep listening/browsing in the current role
    }

    func setClip(_ on: Bool) { clipOn = on; Settings.clipOn = on }
    func setFiles(_ on: Bool) { filesOn = on; Settings.filesOn = on }

    func setKVM(_ on: Bool) {
        kvmOn = on
        kvm.setEnabled(on)
    }

    func setArrange(side: Side, align: Double) {
        kvmSide = side; kvmAlign = align
        kvm.setArrange(side: side, align: align)
    }

    func connect() {
        guard Wire.normalizeCode(joinCode).count >= 8 else { return }
        Settings.joinCode = joinCode
        status = .connecting   // instant feedback, link refines to connected/failed
        link.setJoinCode(joinCode)
        link.connect()
    }

    func regenerateCode() {
        let c = Settings.newCode()
        Settings.code = c; code = c
        link.setHostCode(c)
    }

    func sendFiles(_ urls: [URL]) {
        guard isConnected, clipOn, filesOn else { return }
        let link = self.link
        for url in urls {
            DispatchQueue.global(qos: .utility).async {
                if let (h, d) = Files.frame(for: url) { link.send(h, d) }
            }
        }
    }

    private func apply(_ r: Role) {
        switch r {
        case .host: link.startHost()
        case .join: link.startJoin()
        }
    }
}
