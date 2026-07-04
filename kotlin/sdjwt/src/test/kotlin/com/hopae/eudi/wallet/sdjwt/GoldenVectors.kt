package com.hopae.eudi.wallet.sdjwt

import com.hopae.eudi.wallet.cbor.Cbor
import java.io.File

/** Loads the repo's cross-language `vectors/` (shared by Kotlin and Swift to lock byte-for-byte parity). */
object GoldenVectors {

    fun dir(): File {
        var d = File(System.getProperty("user.dir")).absoluteFile
        repeat(8) {
            val v = File(d, "vectors")
            if (v.isDirectory) return v
            d = d.parentFile ?: return@repeat
        }
        error("vectors/ not found upward from ${System.getProperty("user.dir")}")
    }

    fun load(relative: String): JsonValue.Obj =
        JsonValue.parse(File(dir(), relative).readText()) as JsonValue.Obj

    fun hexToBytes(hex: String): ByteArray =
        hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    fun toHex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

    /** Builds a [Cbor] value from a CborSpec (`{t: uint|nint|bytes|text|bool|null|array|map|tag, ...}`). */
    fun buildCbor(spec: JsonValue): Cbor {
        val o = spec as? JsonValue.Obj ?: error("cbor spec must be an object")
        return when ((o["t"] as? JsonValue.Str)?.value) {
            "uint" -> Cbor.UInt((o["v"] as JsonValue.NumInt).value.toULong())
            "nint" -> Cbor.int((o["v"] as JsonValue.NumInt).value)
            "bytes" -> Cbor.Bytes(hexToBytes((o["v"] as JsonValue.Str).value))
            "text" -> Cbor.Text((o["v"] as JsonValue.Str).value)
            "bool" -> Cbor.Bool((o["v"] as JsonValue.Bool).value)
            "null" -> Cbor.Null
            "array" -> Cbor.Array((o["v"] as JsonValue.Arr).items.map { buildCbor(it) })
            "map" -> Cbor.CborMap((o["v"] as JsonValue.Arr).items.map {
                val pair = (it as JsonValue.Arr).items
                buildCbor(pair[0]) to buildCbor(pair[1])
            })
            "tag" -> Cbor.Tagged((o["tag"] as JsonValue.NumInt).value.toULong(), buildCbor(o["v"]!!))
            else -> error("unknown cbor spec type")
        }
    }
}
