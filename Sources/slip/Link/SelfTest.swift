import Foundation
import Network

enum SelfTest {
    static func run() -> Never {
        let key = Wire.deriveKey("TEST-CODE")
        let q = DispatchQueue(label: "slip.selftest")
        let done = DispatchSemaphore(value: 0)
        var ok = false

        let listener = try! NWListener(using: makePSKParameters(key: key))
        listener.newConnectionHandler = { c in
            c.stateUpdateHandler = { if case .ready = $0 {
                c.send(content: Wire.frame(Header(kind: Kind.text, name: nil, device: "host"), Data("ping".utf8)),
                       completion: .contentProcessed { _ in })
            } }
            c.start(queue: q)
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let client = NWConnection(to: .hostPort(host: "127.0.0.1", port: port),
                                      using: makePSKParameters(key: key))
            client.stateUpdateHandler = { if case .ready = $0 { readPing(client) { got in ok = got; done.signal() } } }
            client.start(queue: q)
        }
        listener.start(queue: q)

        if done.wait(timeout: .now() + 8) == .timedOut { fail("handshake timeout") }
        if ok { print("selftest ok"); exit(0) } else { fail("bad payload") }
    }

    private static func readPing(_ c: NWConnection, _ done: @escaping (Bool) -> Void) {
        recv(c, 4) { l in
            let hlen = Int(Wire.readBE32(l))
            recv(c, hlen) { _ in
                recv(c, 8) { pl in
                    recv(c, Int(Wire.readBE64(pl))) { pd in done(String(decoding: pd, as: UTF8.self) == "ping") }
                }
            }
        }
    }

    private static func recv(_ c: NWConnection, _ n: Int, _ acc: Data = Data(), _ done: @escaping (Data) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: max(1, n - acc.count)) { d, _, isComplete, err in
            var acc = acc
            if let d { acc.append(d) }
            if acc.count >= n { done(acc); return }
            if isComplete || err != nil { return }
            recv(c, n, acc, done)
        }
    }

    private static func fail(_ why: String) -> Never { print("selftest failed: \(why)"); exit(1) }
}
