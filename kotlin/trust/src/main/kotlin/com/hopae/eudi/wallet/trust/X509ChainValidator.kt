package com.hopae.eudi.wallet.trust

import java.security.cert.CertPathValidator
import java.security.cert.CertificateFactory
import java.security.cert.PKIXParameters
import java.security.cert.TrustAnchor
import java.security.cert.X509Certificate
import java.util.Date

/**
 * Trust anchors (IACA / issuer-CA roots) the wallet trusts — populated from the EU LOTL /
 * trust list by the host. Load anchors with [X509Support.parse].
 */
class TrustAnchors(val roots: List<X509Certificate>) {
    init {
        require(roots.isNotEmpty()) { "at least one trust anchor is required" }
    }

    companion object {
        fun ofDer(ders: List<ByteArray>): TrustAnchors = TrustAnchors(X509Support.parseAll(ders))
    }
}

/**
 * Supplies the current trust anchors at validation time (Level 1 dynamic trust). A static set
 * is [fixed]; a Level 2 LOTL provider (M6) would cache a signed trust list and refresh it on a
 * TTL, so anchors update without rebuilding the validator. Consulted on every [X509ChainValidator.validate].
 */
fun interface TrustAnchorSource {
    suspend fun anchors(): TrustAnchors

    companion object {
        /** A fixed anchor set — the common case (host injects a known list). */
        fun fixed(anchors: TrustAnchors): TrustAnchorSource = TrustAnchorSource { anchors }
        fun fixed(roots: List<X509Certificate>): TrustAnchorSource = fixed(TrustAnchors(roots))
    }
}

/**
 * Validates an X.509 chain (leaf-first, excluding the anchor) to the anchors provided by a
 * [TrustAnchorSource] via JCA PKIX. The source is consulted per validation, so a dynamic
 * (cached, TTL-refreshed) trust list plugs in without changing this class. Revocation
 * (CRL/OCSP) is off by default — enabling it makes JCA do network fetches.
 */
class X509ChainValidator(
    private val anchorSource: TrustAnchorSource,
    private val checkRevocation: Boolean = false,
    private val at: () -> Date = { Date() },
) {
    /** Convenience for the static case — validate against a fixed anchor set. */
    constructor(anchors: TrustAnchors, checkRevocation: Boolean = false, at: () -> Date = { Date() }) :
        this(TrustAnchorSource.fixed(anchors), checkRevocation, at)

    private val cf = CertificateFactory.getInstance("X.509")

    /** Returns the parsed chain (leaf first) if it validates to a current anchor, else throws. */
    suspend fun validate(chainDer: List<ByteArray>): List<X509Certificate> {
        if (chainDer.isEmpty()) throw TrustException("empty certificate chain")
        val anchors = anchorSource.anchors()
        val chain = X509Support.parseAll(chainDer)
        val certPath = cf.generateCertPath(chain)
        val params = PKIXParameters(anchors.roots.map { TrustAnchor(it, null) }.toSet()).apply {
            isRevocationEnabled = checkRevocation
            date = at()
        }
        try {
            CertPathValidator.getInstance("PKIX").validate(certPath, params)
        } catch (e: Exception) {
            throw TrustException("chain does not validate to a trust anchor: ${e.message}")
        }
        return chain
    }
}
