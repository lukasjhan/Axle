package com.hopae.eudi.demo.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import com.hopae.eudi.demo.security.BiometricAuth
import com.hopae.eudi.demo.security.WalletSecurity
import com.hopae.eudi.demo.ui.components.Keypad
import com.hopae.eudi.demo.ui.components.PinDots
import com.hopae.eudi.demo.ui.theme.DocGradients
import com.hopae.eudi.demo.ui.theme.EuGold
import com.hopae.eudi.demo.ui.theme.WalletTheme
import kotlinx.coroutines.delay

@Composable
fun LockScreen(activity: FragmentActivity, onUnlock: () -> Unit) {
    val c = WalletTheme.colors
    val ctx = LocalContext.current
    var pin by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }
    val canBio = remember { WalletSecurity.biometricEnabled(ctx) && BiometricAuth.canUse(activity) }

    fun promptBio() = BiometricAuth.prompt(activity, "Unlock wallet", "Confirm your identity", onSuccess = onUnlock)

    // Offer biometric immediately on show.
    LaunchedEffect(Unit) { if (canBio) promptBio() }

    LaunchedEffect(pin) {
        if (pin.length < 6) return@LaunchedEffect
        if (WalletSecurity.verifyPin(ctx, pin)) onUnlock()
        else { error = true; delay(650); pin = ""; error = false }
    }

    Column(
        Modifier.fillMaxSize().background(c.screen).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(Modifier.size(64.dp).clip(RoundedCornerShape(18.dp)).background(Brush.linearGradient(DocGradients.Pid)), contentAlignment = Alignment.Center) {
            Text("★", color = EuGold, style = MaterialTheme.typography.titleMedium)
        }
        Spacer(Modifier.height(20.dp))
        Text("Enter your PIN", style = MaterialTheme.typography.titleMedium, color = c.ink)
        Spacer(Modifier.height(8.dp))
        Text(
            if (error) "Wrong PIN — try again." else "Unlock your wallet to continue.",
            style = MaterialTheme.typography.bodyMedium, color = if (error) c.danger else c.inkMuted, textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(28.dp))
        PinDots(filled = pin.length, error = error)
        Spacer(Modifier.height(40.dp))
        Keypad(
            onDigit = { if (pin.length < 6) pin += it },
            onDelete = { pin = pin.dropLast(1) },
            onBiometric = if (canBio) ({ promptBio() }) else null,
        )
    }
}
