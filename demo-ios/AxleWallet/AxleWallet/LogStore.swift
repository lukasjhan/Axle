import Foundation
import Observation
import OSLog
import WalletAPI

/// In-app debug log sink — the iOS counterpart of android `LogStore`. App-level events (scan, deep link,
/// errors) call `log`; SDK logs arrive through `LogStoreLogger` (the injected `WalletLogger`). Everything
/// also mirrors to the unified logging system (`OSLog`), viewable in Console.app / `log stream`.
@MainActor
@Observable
final class LogStore {
    static let shared = LogStore()

    private(set) var lines: [String] = []
    private let maxLines = 2000
    private let osLog = Logger(subsystem: "com.hopae.axle.wallet", category: "wallet")

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {}

    func log(_ message: String) {
        osLog.log("\(message, privacy: .public)")
        let line = "\(formatter.string(from: Date()))  \(message)"
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    func clear() { lines = [] }

    func asText() -> String { lines.joined(separator: "\n") }
}

/// `WalletLogger` that feeds the in-app Debug log — passed to the SDK in place of `OSLogWalletLogger`
/// (which only reaches OSLog). Error/warn levels get the same ❌ / ⚠️ prefixes the Debug screen filters on.
struct LogStoreLogger: WalletLogger {
    func log(level: LogLevel, message: String, error: Error?) {
        let prefix: String
        switch level {
        case .error: prefix = "❌ "
        case .warn: prefix = "⚠️ "
        default: prefix = ""
        }
        let text = error.map { "\(message) — \($0)" } ?? message
        Task { @MainActor in LogStore.shared.log(prefix + text) }
    }
}
