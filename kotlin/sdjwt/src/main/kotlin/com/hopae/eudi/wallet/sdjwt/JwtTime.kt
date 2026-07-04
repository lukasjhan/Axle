package com.hopae.eudi.wallet.sdjwt

import java.time.Instant

class JwtTimeException(message: String) : Exception(message)

/**
 * RFC 7519 time-claim validation (exp / nbf / iat) with configurable clock skew.
 * Fail-closed: malformed time claims are rejected, not ignored.
 */
class JwtTimeValidator(
    private val now: () -> Instant,
    private val skewSeconds: Long = 60,
) {
    /**
     * @param requireExp reject tokens without `exp` (default: only validate if present)
     * @param maxIatAgeSeconds if set, reject tokens whose `iat` is older than this (freshness)
     */
    fun validate(
        claims: JsonValue.Obj,
        requireExp: Boolean = false,
        maxIatAgeSeconds: Long? = null,
    ) {
        val nowSec = now().epochSecond

        val exp = numericDate(claims, "exp")
        if (exp == null) {
            if (requireExp) throw JwtTimeException("missing required 'exp'")
        } else if (nowSec > exp + skewSeconds) {
            throw JwtTimeException("token expired (exp=$exp, now=$nowSec)")
        }

        numericDate(claims, "nbf")?.let { nbf ->
            if (nowSec + skewSeconds < nbf) throw JwtTimeException("token not yet valid (nbf=$nbf, now=$nowSec)")
        }

        val iat = numericDate(claims, "iat")
        if (iat != null) {
            if (iat > nowSec + skewSeconds) throw JwtTimeException("iat is in the future (iat=$iat, now=$nowSec)")
            if (maxIatAgeSeconds != null && nowSec - iat > maxIatAgeSeconds + skewSeconds) {
                throw JwtTimeException("token too old (iat=$iat, now=$nowSec, max age=$maxIatAgeSeconds)")
            }
        } else if (maxIatAgeSeconds != null) {
            throw JwtTimeException("freshness required but 'iat' missing")
        }
    }

    private fun numericDate(claims: JsonValue.Obj, name: String): Long? {
        return when (val v = claims[name]) {
            null -> null
            is JsonValue.NumInt -> v.value
            // NumericDate MAY be non-integer per RFC 7519; reject fractional-but-out-of-range
            is JsonValue.NumDouble -> v.value.toLong()
            else -> throw JwtTimeException("'$name' must be a number")
        }
    }
}
