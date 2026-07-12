import SdJwt

/// Stores wallet attestations (WUAs) keyed by an arbitrary string (e.g. the authorization-server audience)
/// and lazily refreshes on read: `getOrRefresh` returns the stored WUA while it is still valid, otherwise it
/// fetches a fresh one and stores it. "Valid" = the WUA's `exp` (epoch seconds) is more than `skewSeconds`
/// ahead of `clock`; a WUA whose `exp` cannot be parsed is kept (no expiry info to act on).
final class WuaStore {
    private let clock: () -> Int64
    private let skewSeconds: Int64
    private var entries: [String: Entry] = [:]

    private struct Entry { let wua: String; let expEpoch: Int64? }

    init(clock: @escaping () -> Int64, skewSeconds: Int64 = 60) {
        self.clock = clock
        self.skewSeconds = skewSeconds
    }

    /// The WUA for `key`, fetching (and storing) a fresh one if absent or within `skewSeconds` of expiry.
    func getOrRefresh(_ key: String, fetch: () async throws -> String) async throws -> String {
        if let entry = entries[key], !isStale(entry) { return entry.wua }
        let wua = try await fetch()
        entries[key] = Entry(wua: wua, expEpoch: expOf(wua))
        return wua
    }

    private func isStale(_ entry: Entry) -> Bool {
        guard let exp = entry.expEpoch else { return false }
        return clock() >= exp - skewSeconds
    }

    /// Reads the `exp` (epoch seconds) from a compact JWT payload; nil if it can't be parsed.
    private func expOf(_ jwt: String) -> Int64? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2,
              let payload = try? Base64Url.decodeToString(String(parts[1])),
              let json = try? JsonValue.parse(payload),
              case let .numInt(exp)? = json["exp"] else { return nil }
        return exp
    }
}
