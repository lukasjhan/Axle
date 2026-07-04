import CborCose
import Foundation
import SdJwt

/// Loads the repo's cross-language `vectors/` (shared by Kotlin and Swift to lock byte-for-byte parity).
enum GoldenVectors {

    static func dir() -> URL {
        var d = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let v = d.appendingPathComponent("vectors")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: v.path, isDirectory: &isDir), isDir.boolValue { return v }
            d = d.deletingLastPathComponent()
        }
        fatalError("vectors/ not found upward from \(FileManager.default.currentDirectoryPath)")
    }

    static func load(_ relative: String) throws -> JsonValue {
        let text = try String(contentsOf: dir().appendingPathComponent(relative), encoding: .utf8)
        return try JsonValue.parse(text)
    }

    static func hexToBytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    static func toHex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Builds a `Cbor` value from a CborSpec (`{t: uint|nint|bytes|text|bool|null|array|map|tag, ...}`).
    static func buildCbor(_ spec: JsonValue) throws -> Cbor {
        guard case let .obj(o) = spec else { throw Err.bad("cbor spec must be an object") }
        func f(_ k: String) -> JsonValue? { o.first { $0.0 == k }?.1 }
        guard case let .str(t)? = f("t") else { throw Err.bad("missing t") }
        switch t {
        case "uint": guard case let .numInt(v)? = f("v") else { throw Err.bad("uint v") }; return .uint(UInt64(v))
        case "nint": guard case let .numInt(v)? = f("v") else { throw Err.bad("nint v") }; return .int(v)
        case "bytes": guard case let .str(h)? = f("v") else { throw Err.bad("bytes v") }; return .bytes(hexToBytes(h))
        case "text": guard case let .str(s)? = f("v") else { throw Err.bad("text v") }; return .text(s)
        case "bool": guard case let .bool(b)? = f("v") else { throw Err.bad("bool v") }; return .bool(b)
        case "null": return .null
        case "array": guard case let .arr(items)? = f("v") else { throw Err.bad("array v") }; return .array(try items.map(buildCbor))
        case "map":
            guard case let .arr(items)? = f("v") else { throw Err.bad("map v") }
            return .map(try items.map { entry in
                guard case let .arr(p) = entry else { throw Err.bad("map entry") }
                return (try buildCbor(p[0]), try buildCbor(p[1]))
            })
        case "tag":
            guard case let .numInt(tag)? = f("tag"), let val = f("v") else { throw Err.bad("tag") }
            return .tagged(UInt64(tag), try buildCbor(val))
        default: throw Err.bad("unknown cbor spec type \(t)")
        }
    }

    enum Err: Error { case bad(String) }
}
