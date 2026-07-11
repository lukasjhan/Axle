package com.hopae.eudi.wallet.android.attestation

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.hopae.eudi.wallet.spi.WalletLogger
import kotlinx.coroutines.tasks.await

/**
 * [IntegrityTokenProvider] backed by the **Google Play Integrity API**. Requests an integrity token bound to
 * the wallet provider's challenge [nonce] and the app's [cloudProjectNumber] (the Google Cloud project linked
 * in Play Console); the backend later has Google decode it to a device/app-integrity verdict. The token is an
 * opaque JWE — the wallet only relays it.
 *
 * [fallback] (typically [DevIntegrityTokenProvider]) is used when the real request fails — a side-loaded
 * debug build Play doesn't recognise, no Play Services, or a network error — so development still proceeds;
 * every attempt and outcome is logged via [logger]. **In production pass `fallback = null`** so a failed
 * integrity check surfaces instead of silently degrading to the dev token.
 */
class PlayIntegrityTokenProvider(
    private val context: Context,
    private val cloudProjectNumber: Long,
    private val fallback: IntegrityTokenProvider? = null,
    private val logger: WalletLogger? = null,
) : IntegrityTokenProvider {
    override suspend fun integrityToken(nonce: String): String = try {
        val manager = IntegrityManagerFactory.create(context.applicationContext)
        val response = manager.requestIntegrityToken(
            IntegrityTokenRequest.builder().setNonce(nonce).setCloudProjectNumber(cloudProjectNumber).build(),
        ).await()
        logger?.log(WalletLogger.Level.Info, "Play Integrity token obtained")
        response.token()
    } catch (e: Exception) {
        val fb = fallback ?: throw e
        logger?.log(WalletLogger.Level.Warn, "Play Integrity unavailable (${e.message}); using dev fallback")
        fb.integrityToken(nonce)
    }
}
