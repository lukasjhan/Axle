package com.hopae.eudi.wallet

import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.sdjwt.JsonValue
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Stores wallet attestations (WUAs) keyed by an arbitrary string (e.g. the authorization-server audience)
 * and lazily refreshes on read: [getOrRefresh] returns the stored WUA while it is still valid, otherwise it
 * fetches a fresh one and stores it. "Valid" = the WUA's `exp` (epoch seconds) is more than [skewSeconds]
 * ahead of [clock]; a WUA whose `exp` cannot be parsed is kept (no expiry info to act on). Concurrency-safe.
 */
internal class WuaStore(
    private val clock: () -> Long,
    private val skewSeconds: Long = 60,
) {
    private val mutex = Mutex()
    private val entries = mutableMapOf<String, Entry>()

    private data class Entry(val wua: String, val expEpoch: Long?)

    /** The WUA for [key], fetching (and storing) a fresh one if absent or within [skewSeconds] of expiry. */
    suspend fun getOrRefresh(key: String, fetch: suspend () -> String): String = mutex.withLock {
        entries[key]?.takeUnless { it.isStale(clock()) }?.let { return it.wua }
        fetch().also { entries[key] = Entry(it, expOf(it)) }
    }

    private fun Entry.isStale(nowEpoch: Long): Boolean = expEpoch != null && nowEpoch >= expEpoch - skewSeconds

    /** Reads the `exp` (epoch seconds) from a compact JWT payload; null if it can't be parsed. */
    private fun expOf(jwt: String): Long? = runCatching {
        val payload = Base64Url.decodeToString(jwt.split(".")[1])
        ((JsonValue.parse(payload) as? JsonValue.Obj)?.get("exp") as? JsonValue.NumInt)?.value
    }.getOrNull()
}
