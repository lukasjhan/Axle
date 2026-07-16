import Foundation
// Re-export so the app (which already imports AppleCore) can name the txlog types — TransactionLogEntry,
// RelyingParty, LoggedDocument, TransactionType… — without linking the TransactionLog product directly.
@_exported import TransactionLog

/// Persistent `TransactionLogStore` — the iOS counterpart of android `FileTransactionLogStore`.
///
/// Entries are appended as NDJSON (one `TransactionLogCodec`-encoded object per line) to a file in the
/// shared **App Group** container (`group.com.hopae.axle.wallet`), so the activity log survives relaunch
/// and is reachable by the DC API provider extension (Phase 5). JSON escapes embedded control characters,
/// so no line ever contains a raw newline — the line split is safe.
public actor FileTransactionLogStore: TransactionLogStore {
    private let url: URL
    private var cache: [TransactionLogEntry]?

    /// - Parameter appGroup: shared container id. Falls back to Application Support if the group is
    ///   unavailable (e.g. an entitlement mismatch) so the wallet still runs, just without cross-process sharing.
    public init(appGroup: String = "group.com.hopae.axle.wallet", fileName: String = "transactions.ndjson") {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appendingPathComponent(fileName)
    }

    public func append(_ entry: TransactionLogEntry) {
        var entries = load()
        entries.append(entry)
        cache = entries

        let line = TransactionLogCodec.encode(entry) + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func all() -> [TransactionLogEntry] { load() }

    /// Erase all persisted entries (wallet reset).
    public func clear() {
        cache = []
        try? FileManager.default.removeItem(at: url)
    }

    private func load() -> [TransactionLogEntry] {
        if let cache { return cache }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            cache = []
            return []
        }
        let entries = text.split(separator: "\n").compactMap { try? TransactionLogCodec.decode(String($0)) }
        cache = entries
        return entries
    }
}
