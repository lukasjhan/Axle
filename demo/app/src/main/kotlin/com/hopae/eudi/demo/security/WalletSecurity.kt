package com.hopae.eudi.demo.security

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * On-device secret store for the app lock: the 6-digit PIN (kept only as a PBKDF2 hash) plus the
 * onboarding / biometric flags. Values live in [EncryptedSharedPreferences] (AES-256, key wrapped by a
 * hardware-backed master key), and the PIN is additionally salted+hashed so the raw digits are never stored.
 */
object WalletSecurity {
    private const val FILE = "wallet_secure"
    private const val K_ONBOARDED = "onboarded"
    private const val K_BIOMETRIC = "biometric_enabled"
    private const val K_SALT = "pin_salt"
    private const val K_HASH = "pin_hash"
    private const val ITERATIONS = 120_000

    private fun prefs(ctx: Context): SharedPreferences {
        val master = MasterKey.Builder(ctx).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        return EncryptedSharedPreferences.create(
            ctx, FILE, master,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun isOnboarded(ctx: Context): Boolean = prefs(ctx).getBoolean(K_ONBOARDED, false)

    fun hasPin(ctx: Context): Boolean = prefs(ctx).contains(K_HASH)

    fun biometricEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean(K_BIOMETRIC, false)

    fun setBiometricEnabled(ctx: Context, enabled: Boolean) {
        prefs(ctx).edit().putBoolean(K_BIOMETRIC, enabled).apply()
    }

    fun setPin(ctx: Context, pin: String) {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        prefs(ctx).edit()
            .putString(K_SALT, salt.b64())
            .putString(K_HASH, hash(pin, salt).b64())
            .apply()
    }

    fun verifyPin(ctx: Context, pin: String): Boolean {
        val p = prefs(ctx)
        val salt = p.getString(K_SALT, null)?.unb64() ?: return false
        val expected = p.getString(K_HASH, null)?.unb64() ?: return false
        return MessageDigest.isEqual(hash(pin, salt), expected)
    }

    /** Finalises first-run setup: stores the PIN, the biometric preference, and the onboarded flag. */
    fun completeOnboarding(ctx: Context, pin: String, biometric: Boolean) {
        setPin(ctx, pin)
        prefs(ctx).edit()
            .putBoolean(K_BIOMETRIC, biometric)
            .putBoolean(K_ONBOARDED, true)
            .apply()
    }

    private fun hash(pin: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(pin.toCharArray(), salt, ITERATIONS, 256)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }

    private fun ByteArray.b64(): String = Base64.encodeToString(this, Base64.NO_WRAP)
    private fun String.unb64(): ByteArray = Base64.decode(this, Base64.NO_WRAP)
}
