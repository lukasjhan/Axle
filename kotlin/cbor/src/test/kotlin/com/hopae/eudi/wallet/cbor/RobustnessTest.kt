package com.hopae.eudi.wallet.cbor

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/** Anti-happy-path evidence: random structural fuzz, deep nesting, byte-level truncation. */
class RobustnessTest {

    private var seed = 0x123456789ABCDEFL

    private fun rnd(bound: Int): Int {
        seed = seed * 6364136223846793005L + 1442695040888963407L
        val v = ((seed ushr 33) % bound).toInt()
        return if (v < 0) v + bound else v
    }

    private fun randomValue(depth: Int): Cbor {
        return when (rnd(if (depth > 0) 9 else 6)) {
            0 -> Cbor.int(rnd(1_000_000).toLong() - 500_000)
            1 -> Cbor.UInt(ULong.MAX_VALUE - rnd(1000).toULong())
            2 -> Cbor.Text("s${rnd(1000)}-ü水\"\\\n${rnd(10)}")
            3 -> Cbor.Bytes(ByteArray(rnd(20)) { rnd(256).toByte() })
            4 -> listOf(Cbor.Bool(true), Cbor.Bool(false), Cbor.Null, Cbor.Undefined, Cbor.Simple(99u))[rnd(5)]
            5 -> Cbor.Fp.of(
                listOf(0.0, -0.0, 1.5, 1.1, 65504.0, 1e300, Double.NaN, Double.POSITIVE_INFINITY)[rnd(8)]
            )
            6 -> Cbor.Array((0 until rnd(4)).map { randomValue(depth - 1) })
            7 -> Cbor.CborMap((0 until rnd(4)).map { i -> Cbor.Text("k$i-${rnd(100)}") as Cbor to randomValue(depth - 1) })
            else -> Cbor.Tagged(rnd(1000).toULong(), randomValue(depth - 1))
        }
    }

    @Test
    fun randomTreesReachCanonicalFixpoint() {
        repeat(300) {
            val value = randomValue(5)
            val encoded = CborEncoder.encode(value)
            val decoded = CborDecoder.decode(encoded)
            assertContentEquals(encoded, CborEncoder.encode(decoded), "iteration $it")
        }
    }

    @Test
    fun deepNestingRoundtripsAndGuardHolds() {
        var value: Cbor = Cbor.int(7)
        repeat(200) { value = Cbor.Array(listOf(value)) }
        assertEquals(value, CborDecoder.decode(CborEncoder.encode(value)))

        val tooDeep = ByteArray(600) { 0x81.toByte() } + byteArrayOf(0x00)
        assertFailsWith<CborDecodeException> { CborDecoder.decode(tooDeep) }
    }

    @Test
    fun everyTruncationThrowsCleanly() {
        val bytes = CborEncoder.encode(randomValue(4))
        for (len in 0 until bytes.size) {
            assertFailsWith<CborDecodeException>("prefix length $len") {
                CborDecoder.decode(bytes.copyOf(len), strict = false)
            }
        }
    }
}
