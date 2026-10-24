import Foundation

final class KVM {
    private let sendEvent: (InputEvent) -> Void
    private let receiver = KVMReceiver()
    private var controller: KVMController?
    private var role: Role = .host
    private var side: Side = Settings.otherSide
    private var align: Double = Settings.kvmAlign
    private var enabled = Settings.kvmOn
    private var connected = false
    private var watchdog: Timer?

    init(send: @escaping (InputEvent) -> Void) {
        sendEvent = send
        receiver.onHandback = { [weak self] r in self?.sendEvent(.handback(ratio: r)) }
    }

    func setConnected(_ c: Bool) { connected = c; reconcile() }
    func setRole(_ r: Role) { role = r; reconcile() }
    func setArrange(side s: Side, align a: Double) {
        side = s; align = a
        Settings.otherSide = s; Settings.kvmAlign = a
        controller?.setArrange(side: s, align: a)
    }
    func recheck() { reconcile() }

    func setEnabled(_ e: Bool) {
        enabled = e; Settings.kvmOn = e
        if e, role == .host, !Permissions.kvmReady { Permissions.request() }
        reconcile()
    }

    func receive(_ e: InputEvent) {
        switch role {
        case .join:
            receiver.handle(e)
        case .host:
            if case let .handback(ratio) = e { controller?.handback(ratio: ratio) }
        }
    }

    private func reconcile() {
        if role != .join || !connected {
            receiver.stop()
        }
        if role == .join, connected, !Permissions.accessibility { Permissions.requestAccessibility() }   // receiver injects, needs it

        let wantController = role == .host && enabled && connected
        if wantController, controller == nil {
            guard Permissions.kvmReady else {
                Log.line("kvm host: perms missing ax=\(Permissions.accessibility) im=\(Permissions.inputMonitoring)")
                return
            }
            let c = KVMController(side: side, align: align)
            c.onEvent = { [weak self] e in self?.sendEvent(e) }
            if c.start() { controller = c; startWatchdog(); Log.line("kvm host: controller started") }
            else { Log.line("kvm host: tap create FAILED") }
        } else if !wantController, controller != nil {
            controller?.stop(); controller = nil; stopWatchdog()
        }
    }

    // revoked permission + live tap = lockout trap; tear down
    private func startWatchdog() {
        stopWatchdog()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard Permissions.kvmReady else {
                self.controller?.stop(); self.controller = nil; self.stopWatchdog()
                return
            }
            self.controller?.ensureEnabled()
            self.controller?.reassert()
        }
        RunLoop.main.add(t, forMode: .common); watchdog = t
    }
    private func stopWatchdog() { watchdog?.invalidate(); watchdog = nil }
}
