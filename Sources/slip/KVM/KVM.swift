import Foundation

final class KVM {
    private let sendEvent: (InputEvent) -> Void
    private let receiver = KVMReceiver()
    private let localGuard = LocalCursorGuard()
    private var controller: KVMController?
    private var role: Role = .host
    private var side: Side = Settings.otherSide
    private var align: Double = Settings.kvmAlign
    private var enabled = Settings.kvmOn
    private var connected = false
    private var watchdog: Timer?

    private var lastClaim = DispatchTime.now()

    init(send: @escaping (InputEvent) -> Void) {
        sendEvent = send
        receiver.onHandback = { [weak self] r in self?.sendEvent(.handback(ratio: r)) }
        localGuard.onLocalInput = { [weak self] in self?.claimActive() }
    }

    // local input = this Mac active
    private func claimActive() {
        guard connected, enabled else { return }
        CursorHide.show()
        let now = DispatchTime.now()
        if now > lastClaim + .milliseconds(400) { lastClaim = now; sendEvent(.active) }   // debounce
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
        if case .active = e {
            if enabled, localGuard.active || controller != nil { CursorHide.hide() }   // only hide if we have a way to re-show
            return
        }
        switch role {
        case .join:
            receiver.handle(e)
        case .host:
            if case let .handback(ratio) = e { controller?.handback(ratio: ratio) }
        }
    }

    private func reconcile() {
        if role == .join, connected, enabled {
            if !Permissions.accessibility { Permissions.requestAccessibility() }   // receiver injects, needs it
            localGuard.start()
            if localGuard.active { CursorHide.hide() }   // hide until the host crosses in or local input re-shows
        } else {
            receiver.stop()
            localGuard.stop()
            if role == .join { CursorHide.show() }
        }

        let wantController = role == .host && enabled && connected
        if wantController, controller == nil {
            guard Permissions.kvmReady else {
                Log.line("kvm host: perms missing ax=\(Permissions.accessibility) im=\(Permissions.inputMonitoring)")
                return
            }
            let c = KVMController(side: side, align: align)
            c.onEvent = { [weak self] e in self?.sendEvent(e) }
            c.onLocalInput = { [weak self] in self?.claimActive() }
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
