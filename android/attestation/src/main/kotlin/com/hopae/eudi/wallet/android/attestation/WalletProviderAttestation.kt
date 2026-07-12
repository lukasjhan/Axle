package com.hopae.eudi.wallet.android.attestation

import com.hopae.eudi.wallet.sdjwt.Jws
import com.hopae.eudi.wallet.sdjwt.JsonValue
import com.hopae.eudi.wallet.sdjwt.JwkEc
import com.hopae.eudi.wallet.sdjwt.SecureAreaJwsSigner
import com.hopae.eudi.wallet.spi.HttpMethod
import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpResponse
import com.hopae.eudi.wallet.spi.HttpTransport
import com.hopae.eudi.wallet.spi.KeyInfo
import com.hopae.eudi.wallet.spi.SecureArea
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.spi.StorageDriver
import com.hopae.eudi.wallet.spi.WalletAttestationProvider
import com.hopae.eudi.wallet.spi.WalletClock

/**
 * Reference [WalletAttestationProvider] adapter that talks to the SDK's `wallet-provider/` backend
 * (`GET /nonce`, `POST /wallet-instances`, `POST /wallet-attestation`, `POST /key-attestation`). It is a
 * plain-Kotlin composition of the SDK ports — the injected [http] transport and [secureArea] (which signs
 * the instance-key proof of possession) — plus a platform [integrity] token source; it is injected into
 * `WalletPorts.walletAttestation`. A deployment with a different wallet-provider API swaps in its own
 * `WalletAttestationProvider` at the same port.
 *
 * The wallet **instance key** (created and owned by the SDK, bound into the WUA's `cnf`) is passed to each
 * call. This adapter registers it once (guarded by [integrity]), then fetches a WUA per call — the caller
 * scopes freshness per issuer for HAIP §4.4.1 unlinkability.
 */
class WalletProviderAttestation(
    baseUrl: String,
    private val http: HttpTransport,
    private val secureArea: SecureArea,
    private val integrity: IntegrityTokenProvider,
    private val clientId: String,
    private val clock: WalletClock = WalletClock.System,
    private val storage: StorageDriver? = null,
) : WalletAttestationProvider {

    /** The wallet-provider issuer/base URL; also the `aud` of the instance-key PoP the backend verifies. */
    private val issuer: String = baseUrl.trimEnd('/')

    @Volatile
    private var instanceId: String? = null

    override suspend fun walletAttestation(keyInfo: KeyInfo): String {
        val id = registeredInstance(keyInfo)
        val body = obj(
            "instanceId" to JsonValue.Str(id),
            "clientId" to JsonValue.Str(clientId),
            "pop" to JsonValue.Str(instancePop(keyInfo, fetchNonce())),
        )
        return postJson("$issuer/wallet-attestation", body).str("wallet_attestation")
    }

    override suspend fun keyAttestation(keys: List<KeyInfo>, nonce: String?): String {
        val entries = mutableListOf<Pair<String, JsonValue>>(
            "attestedKeys" to JsonValue.Arr(keys.map { JwkEc.toJson(it.publicKey) }),
        )
        if (nonce != null) entries.add("nonce" to JsonValue.Str(nonce))
        return postJson("$issuer/key-attestation", JsonValue.Obj(entries)).str("key_attestation")
    }

    /**
     * Registers the instance once (nonce → integrity token → `POST /wallet-instances`), caching its id in
     * memory and, if a [storage] is provided, persisting it bound to the instance key alias — so a restart
     * reuses the same instance (a fresh integrity token / new instance is only minted when the key changes)
     * instead of re-registering and leaving orphaned instances behind.
     */
    private suspend fun registeredInstance(keyInfo: KeyInfo): String {
        instanceId?.let { return it }
        val storageKey = "$INSTANCE_ID_KEY:${keyInfo.handle.alias}"
        storage?.get(COLLECTION, storageKey)?.let { return it.decodeToString().also { id -> instanceId = id } }
        val nonce = fetchNonce()
        val body = obj(
            "instanceKey" to JwkEc.toJson(keyInfo.publicKey),
            "integrityToken" to JsonValue.Str(integrity.integrityToken(nonce)),
            "nonce" to JsonValue.Str(nonce),
        )
        return postJson("$issuer/wallet-instances", body).str("instanceId").also {
            instanceId = it
            storage?.put(COLLECTION, storageKey, it.encodeToByteArray())
        }
    }

    private suspend fun fetchNonce(): String =
        parse(http.execute(HttpRequest(HttpMethod.GET, "$issuer/nonce"))).str("nonce")

    /** Proof of possession of the instance key to the wallet provider: `{ aud: issuer, nonce, iat }`. */
    private suspend fun instancePop(keyInfo: KeyInfo, nonce: String): String {
        val header = obj(
            "typ" to JsonValue.Str("wallet-provider-pop+jwt"),
            "alg" to JsonValue.Str(jwsAlg(keyInfo.algorithm)),
        )
        val claims = obj(
            "aud" to JsonValue.Str(issuer),
            "nonce" to JsonValue.Str(nonce),
            "iat" to JsonValue.NumInt(clock.now().epochSecond),
        )
        val signer = SecureAreaJwsSigner(secureArea, keyInfo.handle, keyInfo.algorithm)
        return Jws.sign(header, claims.serialize().encodeToByteArray(), signer).compact()
    }

    private suspend fun postJson(url: String, body: JsonValue.Obj): JsonValue.Obj = parse(
        http.execute(
            HttpRequest(
                HttpMethod.POST, url,
                headers = listOf("Content-Type" to "application/json"),
                body = body.serialize().encodeToByteArray(),
            ),
        ),
    )

    private fun parse(resp: HttpResponse): JsonValue.Obj {
        if (resp.status !in 200..299) {
            throw IllegalStateException("wallet-provider ${resp.status}: ${resp.body.decodeToString().take(200)}")
        }
        return JsonValue.parse(resp.body.decodeToString()) as? JsonValue.Obj
            ?: throw IllegalStateException("wallet-provider returned a non-object JSON response")
    }

    private fun obj(vararg entries: Pair<String, JsonValue>) = JsonValue.Obj(entries.toList())

    private fun JsonValue.Obj.str(key: String): String =
        (this[key] as? JsonValue.Str)?.value ?: throw IllegalStateException("wallet-provider response missing '$key'")

    private fun jwsAlg(alg: SigningAlgorithm): String = when (alg) {
        SigningAlgorithm.ES256 -> "ES256"
        SigningAlgorithm.ES384 -> "ES384"
        SigningAlgorithm.ES512 -> "ES512"
    }

    private companion object {
        const val COLLECTION = "wallet-provider"
        const val INSTANCE_ID_KEY = "instance-id"
    }
}
