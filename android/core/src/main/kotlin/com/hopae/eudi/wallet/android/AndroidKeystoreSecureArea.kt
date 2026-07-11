package com.hopae.eudi.wallet.android

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.hopae.eudi.wallet.cbor.cose.Der
import com.hopae.eudi.wallet.cbor.cose.EcCurve
import com.hopae.eudi.wallet.cbor.cose.EcPublicKey
import com.hopae.eudi.wallet.cbor.cose.Ecdsa
import com.hopae.eudi.wallet.spi.AuthorizationHint
import com.hopae.eudi.wallet.spi.KeyAttestation
import com.hopae.eudi.wallet.spi.KeyHandle
import com.hopae.eudi.wallet.spi.KeyInfo
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.SecureArea
import com.hopae.eudi.wallet.spi.SecureAreaCapabilities
import com.hopae.eudi.wallet.spi.SecureAreaId
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.spi.coseAlgorithm
import com.hopae.eudi.wallet.spi.curve
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.KeyAgreement

/**
 * [SecureArea] backed by the **Android Keystore**: holder keys are hardware-bound and **persist across
 * app restarts** (unlike an in-memory software secure area), so credentials issued in one session can still
 * be presented after a restart. Private keys never leave the TEE.
 */
class AndroidKeystoreSecureArea(
    override val id: SecureAreaId = SecureAreaId("android-keystore"),
) : SecureArea {

    private val keystore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val counter = AtomicLong(System.currentTimeMillis())

    override val capabilities = SecureAreaCapabilities(
        algorithms = setOf(SigningAlgorithm.ES256, SigningAlgorithm.ES384, SigningAlgorithm.ES512),
        hardwareBacked = true,
        userAuthentication = false,
        keyAttestation = true,
        keyAgreement = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S,
    )

    override suspend fun createKey(spec: KeySpec): KeyInfo {
        val alias = "eudi-${counter.incrementAndGet()}"
        val digest = when (spec.algorithm) {
            SigningAlgorithm.ES256 -> KeyProperties.DIGEST_SHA256
            SigningAlgorithm.ES384 -> KeyProperties.DIGEST_SHA384
            SigningAlgorithm.ES512 -> KeyProperties.DIGEST_SHA512
        }
        var purposes = KeyProperties.PURPOSE_SIGN
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) purposes = purposes or KeyProperties.PURPOSE_AGREE_KEY
        val paramSpec = KeyGenParameterSpec.Builder(alias, purposes)
            .setAlgorithmParameterSpec(ECGenParameterSpec(spec.algorithm.curve.jcaName))
            .setDigests(digest)
            // Android Key Attestation is bound at key creation: with a challenge the Keystore emits a
            // certificate chain (leaf → … → Google hardware-attestation root) that proves the key's storage
            // and the challenge. Without one, only a self-signed leaf exists (no attestation). See attestation().
            .apply { spec.attestationChallenge?.let { setAttestationChallenge(it) } }
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
            .apply { initialize(paramSpec) }.generateKeyPair()
        return KeyInfo(KeyHandle(id, alias), spec.algorithm, publicKeyOf(publicOf(alias)))
    }

    override suspend fun publicKey(key: KeyHandle): EcPublicKey = publicKeyOf(publicOf(key.alias))

    override suspend fun sign(
        key: KeyHandle,
        algorithm: SigningAlgorithm,
        data: ByteArray,
        hint: AuthorizationHint?,
    ): ByteArray {
        val entry = privateEntry(key)
        val der = Signature.getInstance(algorithm.coseAlgorithm.jcaName).run {
            initSign(entry.privateKey); update(data); sign()
        }
        return Der.derSignatureToRaw(der, algorithm.curve.coordinateSize)
    }

    override suspend fun keyAgreement(
        key: KeyHandle,
        peerPublicKey: EcPublicKey,
        hint: AuthorizationHint?,
    ): ByteArray = KeyAgreement.getInstance("ECDH", "AndroidKeyStore").run {
        init(privateEntry(key).privateKey)
        doPhase(Ecdsa.publicKeyOf(peerPublicKey), true)
        generateSecret()
    }

    /**
     * The Android Key Attestation certificate chain for [key], as concatenated DER (leaf → root; each cert
     * is a self-delimiting DER `SEQUENCE`, so a verifier reads them in order). Format `android-keystore-x5c`.
     *
     * The chain — and the challenge it binds — are fixed when the key is generated, so the key must have been
     * created with `KeySpec.attestationChallenge` set (Android has no way to re-attest an existing key with a
     * new challenge); [challenge] is accepted for port symmetry but not re-bound here. Returns null when the
     * key carries no attestation chain (only a self-signed leaf), i.e. it was created without a challenge.
     */
    override suspend fun attestation(key: KeyHandle, challenge: ByteArray): KeyAttestation? {
        require(key.secureArea == id) { "key belongs to ${key.secureArea}, not $id" }
        val chain = keystore.getCertificateChain(key.alias) ?: return null
        if (chain.size <= 1) return null // self-signed leaf only — no hardware attestation was requested at creation
        return KeyAttestation("android-keystore-x5c", chain.fold(ByteArray(0)) { acc, cert -> acc + cert.encoded })
    }

    override suspend fun deleteKey(key: KeyHandle) {
        keystore.deleteEntry(key.alias)
    }

    private fun privateEntry(key: KeyHandle): KeyStore.PrivateKeyEntry {
        require(key.secureArea == id) { "key belongs to ${key.secureArea}, not $id" }
        return keystore.getEntry(key.alias, null) as? KeyStore.PrivateKeyEntry
            ?: throw IllegalStateException("unknown or deleted key: ${key.alias}")
    }

    private fun publicOf(alias: String): ECPublicKey =
        (keystore.getCertificate(alias) ?: error("unknown key: $alias")).publicKey as ECPublicKey

    private fun publicKeyOf(pub: ECPublicKey): EcPublicKey {
        val curve = when (pub.params.curve.field.fieldSize) {
            256 -> EcCurve.P256
            384 -> EcCurve.P384
            521 -> EcCurve.P521
            else -> error("unsupported curve size ${pub.params.curve.field.fieldSize}")
        }
        return EcPublicKey(curve, pub.w.affineX.toFixed(curve.coordinateSize), pub.w.affineY.toFixed(curve.coordinateSize))
    }

    private fun BigInteger.toFixed(size: Int): ByteArray {
        val stripped = toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
        require(stripped.size <= size) { "coordinate larger than curve size" }
        return ByteArray(size - stripped.size) + stripped
    }
}
