package com.hopae.eudi.demo.security

/**
 * Cross-activity flags for the auto-lock. The wallet re-locks when it returns to the foreground after being
 * backgrounded — but not when it comes back from one of its *own* sub-activities (QR scanner, browser
 * authorization, Credential Manager), which also fire stop/start. Those launch points set
 * [suppressNextResumeLock] so the return trip doesn't demand a re-unlock.
 */
object AppLock {
    @Volatile var suppressNextResumeLock = false

    /** Called right before launching one of our own sub-activities. */
    fun suppressResumeLock() { suppressNextResumeLock = true }
}
