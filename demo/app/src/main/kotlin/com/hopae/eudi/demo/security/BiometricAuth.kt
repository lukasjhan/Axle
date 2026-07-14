package com.hopae.eudi.demo.security

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/** Thin wrapper over androidx.biometric for the app-lock / onboarding biometric step. */
object BiometricAuth {

    private const val STRONG = BiometricManager.Authenticators.BIOMETRIC_STRONG

    /** True when the device has an enrolled strong biometric we can prompt for. */
    fun canUse(activity: FragmentActivity): Boolean =
        BiometricManager.from(activity).canAuthenticate(STRONG) == BiometricManager.BIOMETRIC_SUCCESS

    /** Label for the device's biometric modality (best-effort; a face-only device still reads "Biometric"). */
    fun label(activity: FragmentActivity): String {
        val pm = activity.packageManager
        return when {
            pm.hasSystemFeature("android.hardware.fingerprint") -> "Fingerprint"
            pm.hasSystemFeature("android.hardware.biometrics.face") -> "Face"
            else -> "Biometric"
        }
    }

    fun prompt(
        activity: FragmentActivity,
        title: String,
        subtitle: String,
        onSuccess: () -> Unit,
        onError: (String) -> Unit = {},
        negativeText: String = "Use PIN",
    ) {
        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onSuccess()
            override fun onAuthenticationError(code: Int, msg: CharSequence) { onError(msg.toString()) }
            // onAuthenticationFailed = one non-matching attempt; the prompt stays up, so nothing to do here.
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText(negativeText)
            .setAllowedAuthenticators(STRONG)
            .build()
        prompt.authenticate(info)
    }
}
