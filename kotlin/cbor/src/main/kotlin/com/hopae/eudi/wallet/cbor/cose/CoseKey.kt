package com.hopae.eudi.wallet.cbor.cose

import com.hopae.eudi.wallet.cbor.Cbor

/**
 * COSE_Key for EC2 public keys (RFC 9052 §7 / RFC 9053 §7.1). Used as the mdoc `deviceKey`
 * (ISO 18013-5) and elsewhere a raw public key travels as CBOR.
 *
 * ```
 * { 1: 2 (kty EC2), -1: crv, -2: x (bstr), -3: y (bstr) }
 * ```
 */
object CoseKey {
    private const val KTY = 1L
    private const val CRV = -1L
    private const val X = -2L
    private const val Y = -3L
    private const val KTY_EC2 = 2L

    private fun crvId(curve: EcCurve): Long = when (curve) {
        EcCurve.P256 -> 1L
        EcCurve.P384 -> 2L
        EcCurve.P521 -> 3L
    }

    private fun curveOf(id: Long): EcCurve = when (id) {
        1L -> EcCurve.P256
        2L -> EcCurve.P384
        3L -> EcCurve.P521
        else -> throw CoseException("unsupported COSE_Key curve $id")
    }

    fun encode(key: EcPublicKey): Cbor.CborMap = Cbor.CborMap(
        listOf(
            Cbor.int(KTY) to Cbor.int(KTY_EC2),
            Cbor.int(CRV) to Cbor.int(crvId(key.curve)),
            Cbor.int(X) to Cbor.Bytes(key.x),
            Cbor.int(Y) to Cbor.Bytes(key.y),
        )
    )

    fun decode(map: Cbor.CborMap): EcPublicKey {
        fun get(label: Long): Cbor? = map.entries.firstOrNull { (k, _) -> k.asLong() == label }?.second
        if (get(KTY)?.asLong() != KTY_EC2) throw CoseException("COSE_Key is not EC2")
        val curve = curveOf(get(CRV)?.asLong() ?: throw CoseException("COSE_Key missing crv"))
        val x = (get(X) as? Cbor.Bytes)?.value ?: throw CoseException("COSE_Key missing x")
        val y = (get(Y) as? Cbor.Bytes)?.value ?: throw CoseException("COSE_Key missing y")
        return EcPublicKey(curve, x, y)
    }

    private fun Cbor.asLong(): Long? = when (this) {
        is Cbor.UInt -> if (value <= Long.MAX_VALUE.toULong()) value.toLong() else null
        is Cbor.NInt -> if (n < Long.MAX_VALUE.toULong()) -1L - n.toLong() else null
        else -> null
    }
}
