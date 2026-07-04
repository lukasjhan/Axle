package com.hopae.eudi.wallet.sdjwt

import com.hopae.eudi.wallet.cbor.CborDecoder
import com.hopae.eudi.wallet.cbor.CborEncoder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Cross-language golden vectors for deterministic CBOR (RFC 8949). The identical `vectors/` file
 * is consumed by the Swift suite, so both implementations are byte-for-byte locked to the same
 * encoding (and to the RFC 8949 Appendix A reference values).
 */
class CborGoldenTest {

    @Test
    fun deterministicEncodingMatchesGolden() {
        val vectors = (GoldenVectors.load("cbor/deterministic.json")["vectors"] as JsonValue.Arr).items
        assertTrue(vectors.size >= 20, "expected a substantive vector set")
        for (v in vectors) {
            val o = v as JsonValue.Obj
            val name = (o["name"] as JsonValue.Str).value
            val expected = (o["hex"] as JsonValue.Str).value
            val cbor = GoldenVectors.buildCbor(o["cbor"]!!)

            assertEquals(expected, GoldenVectors.toHex(CborEncoder.encode(cbor)), "encode '$name'")
            // decode the reference bytes then re-encode: proves canonicalization is stable
            val reEncoded = GoldenVectors.toHex(CborEncoder.encode(CborDecoder.decode(GoldenVectors.hexToBytes(expected))))
            assertEquals(expected, reEncoded, "decode+re-encode '$name'")
        }
    }
}
