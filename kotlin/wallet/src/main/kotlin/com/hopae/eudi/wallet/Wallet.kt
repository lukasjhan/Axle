package com.hopae.eudi.wallet

import com.hopae.eudi.wallet.store.CredentialStore

/**
 * The unified EUDI Wallet SDK facade (API-CONTRACT.md §5). Multi-instance, thread-safe; no global
 * state. [close] is idempotent.
 *
 * Phase A wires credential storage; issuance/presentation/proximity services follow in B/C/D.
 */
class Wallet private constructor(
    val credentials: CredentialsService,
    private val ports: WalletPorts,
) : AutoCloseable {

    @Volatile
    private var closed = false

    override fun close() {
        closed = true
    }

    companion object {
        fun create(config: WalletConfig, ports: WalletPorts): Wallet {
            val store = CredentialStore(ports.storage)
            return Wallet(
                credentials = CredentialsService(store),
                ports = ports,
            )
        }
    }
}
