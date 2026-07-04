import Foundation

public struct JwtTimeError: Error, CustomStringConvertible {
    public let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// RFC 7519 time-claim validation (exp / nbf / iat) with configurable clock skew.
/// Fail-closed: malformed time claims are rejected, not ignored.
public struct JwtTimeValidator {
    private let now: () -> Date
    private let skewSeconds: Int64

    public init(now: @escaping () -> Date, skewSeconds: Int64 = 60) {
        self.now = now
        self.skewSeconds = skewSeconds
    }

    /// - Parameters:
    ///   - requireExp: reject tokens without `exp` (default: only validate if present)
    ///   - maxIatAgeSeconds: if set, reject tokens whose `iat` is older than this (freshness)
    public func validate(
        _ claims: JsonValue,
        requireExp: Bool = false,
        maxIatAgeSeconds: Int64? = nil
    ) throws {
        let nowSec = Int64(now().timeIntervalSince1970)

        if let exp = try numericDate(claims, "exp") {
            if nowSec > exp + skewSeconds {
                throw JwtTimeError("token expired (exp=\(exp), now=\(nowSec))")
            }
        } else if requireExp {
            throw JwtTimeError("missing required 'exp'")
        }

        if let nbf = try numericDate(claims, "nbf"), nowSec + skewSeconds < nbf {
            throw JwtTimeError("token not yet valid (nbf=\(nbf), now=\(nowSec))")
        }

        if let iat = try numericDate(claims, "iat") {
            if iat > nowSec + skewSeconds {
                throw JwtTimeError("iat is in the future (iat=\(iat), now=\(nowSec))")
            }
            if let maxAge = maxIatAgeSeconds, nowSec - iat > maxAge + skewSeconds {
                throw JwtTimeError("token too old (iat=\(iat), now=\(nowSec), max age=\(maxAge))")
            }
        } else if maxIatAgeSeconds != nil {
            throw JwtTimeError("freshness required but 'iat' missing")
        }
    }

    private func numericDate(_ claims: JsonValue, _ name: String) throws -> Int64? {
        switch claims[name] {
        case .none: return nil
        case let .numInt(n): return n
        case let .numDouble(d): return Int64(d)
        default: throw JwtTimeError("'\(name)' must be a number")
        }
    }
}
