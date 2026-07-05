package com.hopae.eudi.demo

import com.hopae.eudi.wallet.IssuanceSession

/**
 * Bridges the authorization-code browser round-trip: an issuance session waiting at
 * `AuthorizationRequired` is parked here while the browser is open, and resumed when the
 * `eudi-wallet://authorize` redirect re-enters [MainActivity].
 */
object PendingAuth {
    @Volatile
    var session: IssuanceSession? = null

    fun complete(redirectUri: String) {
        val s = session ?: return
        session = null
        LogStore.log("Authorization redirect received")
        s.completeAuthorization(redirectUri)
    }
}
