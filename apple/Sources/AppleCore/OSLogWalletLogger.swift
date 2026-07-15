import Foundation
import OSLog
import WalletAPI

/// `WalletLogger` that routes SDK logs into the unified logging system (`OSLog`) — the iOS counterpart
/// of the android demo's `LogWalletLogger`. Viewable in Console.app and `log stream`.
public struct OSLogWalletLogger: WalletLogger {
    private let logger: Logger

    public init(subsystem: String = "com.hopae.axle.wallet", category: String = "wallet") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(level: LogLevel, message: String, error: Error?) {
        let text = error.map { "\(message) — \($0)" } ?? message
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warn: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
    }
}
