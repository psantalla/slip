import Foundation
import Network

enum Role: String { case host, join }

enum LinkStatus: Equatable {
    case disconnected
    case failed
    case connecting
    case connected(peer: String)
}

struct Peer {
    let id: String
    let endpoint: NWEndpoint
}

// @unchecked Sendable: all mutable state is confined to the serial queue `q`.
final class Link: @unchecked Sendable {
    static let serviceType = "_slip._tcp"
    private static let pingEvery = 4.0
    private static let deadAfter = 12.0
    private static let dialTimeout = 5.0
    private static let reconnectDelay = 2.0

    var onStatus: ((LinkStatus) -> Void)?
    var onFrame: ((Header, Data) -> Void)?

    private let q = DispatchQueue(label: "slip.link")
    private let device = Settings.deviceName
    private var code: String
    private var isJoin = false
    private var epoch = 0

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var conn: NWConnection?
    private var pending: [NWConnection] = []
    private var peerName: String?

    private var dialingConn: NWConnection?
    private var dialTimeout: DispatchWorkItem?

    private var hb: DispatchSourceTimer?
    private var lastRecv = DispatchTime.now()

    // dial discovered hosts; retry a few times each, reconnect after a real link
    private var wantConnect = false
    private var hadLink = false
    private var lastPeers: [Peer] = []
    private var attempts: [String: Int] = [:]   // failed dials per peer this session
    private var dialingPeerId: String?
    private var lastDialAt: DispatchTime?
    private var connectDeadline: DispatchWorkItem?
    private static let maxAttempts = 3
    private static let connectTimeout = 8.0

    init(code: String) { self.code = code }

    func setCode(_ c: String) { q.async { self.code = c } }

    func startHost() {
        q.async { [weak self] in
            guard let self else { return }
            self.teardown()
            self.isJoin = false
            do {
                let l = try NWListener(using: self.params())
                l.service = NWListener.Service(name: self.device, type: Link.serviceType)
                l.newConnectionHandler = { [weak self] c in self?.begin(c, dial: false) }
                l.start(queue: self.q)
                self.listener = l
            } catch { self.emit(.disconnected) }
        }
    }

    func startJoin() {
        q.async { [weak self] in
            guard let self else { return }
            self.teardown()
            self.isJoin = true
            let b = NWBrowser(for: .bonjour(type: Link.serviceType, domain: nil), using: NWParameters())
            b.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                self.lastPeers = results.compactMap { r in
                    // never list ourselves (stale mDNS)
                    guard case let .service(name, _, _, _) = r.endpoint, name != self.device else { return nil }
                    return Peer(id: name, endpoint: r.endpoint)
                }
                self.attempts = self.attempts.filter { id, _ in self.lastPeers.contains { $0.id == id } }   // a host that reappears retries fresh
                self.tryDial()
            }
            b.start(queue: self.q)
            self.browser = b
        }
    }

    func connect() {
        q.async {
            self.wantConnect = true
            self.hadLink = false
            self.attempts.removeAll()
            self.lastDialAt = nil
            self.cancelDial()
            self.dropCurrent()
            self.armConnectDeadline()
            self.tryDial()
        }
    }

    func stop() { q.async { self.teardown() } }

    func send(_ header: Header, _ payload: Data) {
        guard payload.count <= Wire.maxPayload else { return }
        let prefix = Wire.prefix(header, payloadCount: payload.count)
        q.async {
            guard let c = self.conn else { return }
            c.send(content: prefix, completion: .contentProcessed { _ in })
            if !payload.isEmpty { c.send(content: payload, completion: .contentProcessed { _ in }) }
        }
    }

    private func tryDial() {
        guard isJoin, wantConnect, conn == nil, dialingConn == nil,
              let peer = lastPeers.first(where: { (attempts[$0.id] ?? 0) < Link.maxAttempts }) else { return }
        if let last = lastDialAt, DispatchTime.now() < last + Link.reconnectDelay { scheduleDial(); return }   // rate-limit dials (mDNS churn)
        dial(peer)
    }

    private func dial(_ peer: Peer) {
        guard dialingConn == nil else { return }
        dialingPeerId = peer.id
        lastDialAt = .now()
        connectDeadline?.cancel(); connectDeadline = nil   // a dial is now in flight
        emit(.connecting)
        begin(NWConnection(to: peer.endpoint, using: params()), dial: true)
    }

    private func scheduleDial() {
        guard isJoin, wantConnect else { return }
        q.asyncAfter(deadline: .now() + Link.reconnectDelay) { [weak self] in self?.tryDial() }
    }

    // no host discovered in time -> surface a failure instead of spinning on "connecting"
    private func armConnectDeadline() {
        connectDeadline?.cancel()
        let gen = epoch
        let work = DispatchWorkItem { [weak self] in
            guard let self, gen == self.epoch, self.wantConnect,
                  self.conn == nil, self.dialingConn == nil else { return }
            self.emit(.failed)
        }
        connectDeadline = work
        q.asyncAfter(deadline: .now() + Link.connectTimeout, execute: work)
    }

    private func begin(_ c: NWConnection, dial: Bool) {
        let gen = epoch
        pending.append(c)
        if dial {
            dialingConn = c
            let work = DispatchWorkItem { [weak self] in
                guard let self, gen == self.epoch, self.dialingConn === c else { return }
                c.cancel()
            }
            dialTimeout = work
            q.asyncAfter(deadline: .now() + Link.dialTimeout, execute: work)
        }
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            guard gen == self.epoch else { c.cancel(); return }
            switch state {
            case .ready:
                self.pending.removeAll { $0 === c }
                if self.dialingConn === c { self.clearDial() }
                self.promote(c)
            case .waiting:
                break
            case .failed(let e):
                Log.line("conn failed: \(e)")
                self.pending.removeAll { $0 === c }
                if self.dialingConn === c { self.dialFailed() }
                else if c === self.conn { self.lostLink() }
                else { c.cancel() }
            case .cancelled:
                self.pending.removeAll { $0 === c }
                if self.dialingConn === c { self.dialFailed() }
                else if c === self.conn { self.lostLink() }
                else { c.cancel() }
            default: break
            }
        }
        c.start(queue: q)
    }

    // first authenticated wins; reject late/duplicate, ignore a repeat .ready for the same conn
    private func promote(_ c: NWConnection) {
        guard conn == nil else { if conn !== c { c.cancel() }; return }
        pending.forEach { if $0 !== c { $0.cancel() } }; pending.removeAll()
        conn = c
        peerName = nil
        hadLink = true
        attempts.removeAll()
        connectDeadline?.cancel(); connectDeadline = nil
        lastRecv = .now()
        startHeartbeat()
        emit(.connecting)
        send(Header(kind: Kind.hello, name: nil, device: device), Data())
        readFrame(c)
    }

    private func lostLink() {
        stopHeartbeat()
        let dead = conn
        conn = nil
        dead?.cancel()
        emit(.disconnected)
        scheduleReconnect()
    }

    private func dropCurrent() {
        guard conn != nil else { return }
        stopHeartbeat()
        let old = conn
        conn = nil
        old?.cancel()
        emit(.disconnected)
    }

    private func cancelDial() {
        guard let c = dialingConn else { return }
        clearDial()
        c.cancel()
    }

    private func clearDial() {
        dialingConn = nil
        dialingPeerId = nil
        dialTimeout?.cancel(); dialTimeout = nil
    }

    private func dialFailed() {
        let id = dialingPeerId
        clearDial()
        if hadLink { scheduleReconnect(); return }   // real link dropped: keep the same peer
        if let id { attempts[id, default: 0] += 1 }
        if lastPeers.contains(where: { (attempts[$0.id] ?? 0) < Link.maxAttempts }) {
            scheduleDial()        // retry this peer or try another
        } else {
            emit(.failed)         // all peers exhausted; a newly discovered one still retries
        }
    }

    private func scheduleReconnect() {
        guard isJoin, hadLink, wantConnect else { return }
        q.asyncAfter(deadline: .now() + Link.reconnectDelay) { [weak self] in self?.tryDial() }
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + Link.pingEvery, repeating: Link.pingEvery)
        t.setEventHandler { [weak self] in self?.heartbeat() }
        t.resume()
        hb = t
    }

    private func stopHeartbeat() { hb?.cancel(); hb = nil }

    private func heartbeat() {
        guard let c = conn else { return }
        if DispatchTime.now() > lastRecv + Link.deadAfter { drop(c); return }
        send(Header(kind: Kind.ping, name: nil, device: nil), Data())
    }

    private func readFrame(_ c: NWConnection) {
        receiveExact(c, 4) { [weak self] lenD in
            guard let self else { return }
            let hlen = Int(Wire.readBE32(lenD))
            guard hlen > 0, hlen < (1 << 20) else { self.drop(c); return }
            self.receiveExact(c, hlen) { hd in
                guard let header = try? JSONDecoder().decode(Header.self, from: hd) else { self.drop(c); return }
                self.receiveExact(c, 8) { plenD in
                    let plen64 = Wire.readBE64(plenD)
                    guard plen64 <= UInt64(Wire.maxPayload) else { self.drop(c); return }
                    let plen = Int(plen64)
                    let finish: (Data) -> Void = { pd in
                        guard c === self.conn else { return }   // drop frames from a torn-down link
                        self.deliver(header, pd); self.readFrame(c)
                    }
                    if plen == 0 { finish(Data()) } else { self.receiveExact(c, plen, Data(), finish) }
                }
            }
        }
    }

    private func receiveExact(_ c: NWConnection, _ n: Int, _ acc: Data = Data(), _ done: @escaping (Data) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: max(1, n - acc.count)) { [weak self] data, _, isComplete, err in
            guard let self else { return }
            var acc = acc
            if acc.isEmpty { acc.reserveCapacity(n) }
            if let d = data { acc.append(d) }
            if acc.count >= n { done(acc); return }
            if isComplete || err != nil { self.drop(c); return }
            self.receiveExact(c, n, acc, done)
        }
    }

    private func deliver(_ header: Header, _ payload: Data) {
        lastRecv = .now()
        switch header.kind {
        case Kind.ping:
            return
        case Kind.hello:
            guard peerName == nil else { return }   // ignore duplicate hello
            peerName = header.device
            emit(.connected(peer: peerName ?? "the other Mac"))
        default:
            DispatchQueue.main.async { self.onFrame?(header, payload) }
        }
    }

    private func drop(_ c: NWConnection) {
        if c === conn { lostLink() } else { c.cancel() }
    }

    private func emit(_ status: LinkStatus) {
        Log.line("status \(status)")
        DispatchQueue.main.async { self.onStatus?(status) }
    }

    private func teardown() {
        epoch += 1
        stopHeartbeat()
        cancelDial()
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        pending.forEach { $0.cancel() }; pending.removeAll()
        conn?.cancel(); conn = nil
        peerName = nil
        wantConnect = false
        hadLink = false
        lastPeers = []
        attempts.removeAll()
        connectDeadline?.cancel(); connectDeadline = nil
        emit(.disconnected)
    }

    private var cachedKey: (code: String, key: Data)?
    private func params() -> NWParameters {
        if cachedKey?.code != code { cachedKey = (code, Wire.deriveKey(code)) }   // PBKDF2 is expensive
        return makePSKParameters(key: cachedKey!.key)
    }
}

func makePSKParameters(key: Data) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    let sec = tls.securityProtocolOptions
    let identity = Data("slip".utf8)
    key.withUnsafeBytes { kb in
        identity.withUnsafeBytes { ib in
            let k = DispatchData(bytes: kb)
            let i = DispatchData(bytes: ib)
            sec_protocol_options_add_pre_shared_key(sec, k as __DispatchData, i as __DispatchData)
        }
    }
    if let cs = tls_ciphersuite_t(rawValue: 0x00A8) { sec_protocol_options_append_tls_ciphersuite(sec, cs) }
    sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
    return NWParameters(tls: tls)
}
