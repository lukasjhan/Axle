package com.hopae.eudi.wallet.sdjwt

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/** Anti-happy-path evidence for the JSON layer: fuzz roundtrips, deep nesting, truncation. */
class JsonRobustnessTest {

    private var seed = 0x0FEDCBA987654321L

    private fun rnd(bound: Int): Int {
        seed = seed * 6364136223846793005L + 1442695040888963407L
        val v = ((seed ushr 33) % bound).toInt()
        return if (v < 0) v + bound else v
    }

    private fun randomJson(depth: Int): JsonValue {
        return when (rnd(if (depth > 0) 8 else 6)) {
            0 -> JsonValue.NumInt(rnd(2_000_000).toLong() - 1_000_000)
            1 -> JsonValue.NumInt(9_007_199_254_740_991L + rnd(1000)) // beyond double precision
            2 -> JsonValue.Str("s${rnd(1000)} ü水\"\\\n\t${rnd(10)}")
            3 -> listOf(JsonValue.Bool(true), JsonValue.Bool(false), JsonValue.Null)[rnd(3)]
            4 -> JsonValue.NumDouble(listOf(1.5, -2.25, 3.141592653589793, 1e100)[rnd(4)])
            5 -> JsonValue.Str("")
            6 -> JsonValue.Arr((0 until rnd(4)).map { randomJson(depth - 1) })
            else -> JsonValue.Obj((0 until rnd(4)).map { i -> "k$i" to randomJson(depth - 1) })
        }
    }

    @Test
    fun randomTreesRoundtrip() {
        repeat(300) {
            val value = randomJson(5)
            assertEquals(value, JsonValue.parse(value.serialize()), "iteration $it")
        }
    }

    @Test
    fun deepNestingRoundtripsAndGuardHolds() {
        var value: JsonValue = JsonValue.NumInt(7)
        repeat(200) { value = JsonValue.Arr(listOf(value)) }
        assertEquals(value, JsonValue.parse(value.serialize()))

        val tooDeep = "[".repeat(300) + "0" + "]".repeat(300)
        assertFailsWith<JsonException> { JsonValue.parse(tooDeep) }
    }

    @Test
    fun everyTruncationThrowsCleanly() {
        val doc = JsonValue.Obj(
            listOf(
                "a" to randomJson(3),
                "s" to JsonValue.Str("br{ce\"s}and\\escapes"),
                "n" to JsonValue.Arr(listOf(JsonValue.NumInt(123456), JsonValue.NumDouble(1.5))),
            )
        ).serialize()
        for (len in 0 until doc.length) {
            assertFailsWith<JsonException>("prefix length $len") { JsonValue.parse(doc.substring(0, len)) }
        }
    }
}
