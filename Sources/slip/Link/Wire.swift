import Foundation
import CommonCrypto

// Frame: [4B hdrLen][hdr JSON][8B payloadLen][payload]. Big-endian lengths.
struct Header: Codable {
    var kind: String
    var name: String?
    var device: String?
}

enum Kind {
    static let hello = "hello"
    static let ping = "ping"
    static let text = "text"
    static let image = "image"
    static let file = "file"
    static let input = "input"
}

enum Wire {
    static let maxPayload = 64 * 1024 * 1024

    static func prefix(_ header: Header, payloadCount: Int) -> Data {
        let hdr = (try? JSONEncoder().encode(header)) ?? Data()
        var out = Data(capacity: 12 + hdr.count)
        out.append(be32(UInt32(hdr.count)))
        out.append(hdr)
        out.append(be64(UInt64(payloadCount)))
        return out
    }

    static func frame(_ header: Header, _ payload: Data) -> Data {
        var out = prefix(header, payloadCount: payload.count)
        out.append(payload)
        return out
    }

    static func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    static func be64(_ v: UInt64) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    static func readBE32(_ d: Data) -> UInt32 { d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian } }
    static func readBE64(_ d: Data) -> UInt64 { d.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian } }

    // canonical: alnum, uppercased
    static func normalizeCode(_ s: String) -> String { s.uppercased().filter { $0.isLetter || $0.isNumber } }

    static func deriveKey(_ code: String) -> Data {
        let pw = Array(normalizeCode(code).utf8)
        let salt = Array("slip.psk.v1".utf8)
        var out = [UInt8](repeating: 0, count: 32)
        _ = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            pw.map { Int8(bitPattern: $0) }, pw.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            200_000,
            &out, out.count
        )
        return Data(out)
    }
}
