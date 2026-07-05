package com.hopae.eudi.demo.adapters

import com.hopae.eudi.demo.LogStore
import com.hopae.eudi.wallet.spi.WalletLogger

/** Routes any SDK-emitted logs into the in-app [LogStore]. */
class LogWalletLogger : WalletLogger {
    override fun log(level: WalletLogger.Level, message: String, throwable: Throwable?) {
        LogStore.log("[$level] $message" + (throwable?.let { " — ${it.javaClass.simpleName}: ${it.message}" } ?: ""))
    }
}
