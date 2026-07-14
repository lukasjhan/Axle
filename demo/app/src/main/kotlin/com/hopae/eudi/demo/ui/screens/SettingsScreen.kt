package com.hopae.eudi.demo.ui.screens

import android.content.pm.PackageManager
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.hopae.eudi.demo.ui.ProximityPrefs
import com.hopae.eudi.demo.ui.components.SectionLabel
import com.hopae.eudi.demo.ui.components.WalletCard
import com.hopae.eudi.demo.ui.theme.WalletTheme

@Composable
fun SettingsScreen(onOpenDebug: () -> Unit) {
    val c = WalletTheme.colors
    val context = LocalContext.current
    var biometric by remember { mutableStateOf(true) }
    var appLock by remember { mutableStateOf(true) }

    var bleCentral by remember { mutableStateOf(ProximityPrefs.bleCentral(context)) }
    var nfcNegotiated by remember { mutableStateOf(ProximityPrefs.nfcNegotiated(context)) }

    val strongBox = remember {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
    }
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "—"
    }

    Column(
        Modifier.fillMaxSize().background(c.screen).verticalScroll(rememberScrollState())
            .padding(20.dp, 16.dp, 20.dp, 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.titleLarge, color = c.ink)

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionLabel("Security")
            WalletCard(padding = PaddingValues(0.dp)) {
                ToggleRow("Biometric unlock", biometric) { biometric = it }
                Divider()
                ToggleRow("Require app lock", appLock) { appLock = it }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionLabel("Wallet")
            WalletCard(padding = PaddingValues(0.dp)) {
                ValueRow("Security hardware", if (strongBox) "StrongBox" else "TEE")
                Divider()
                ValueRow("Trusted list", "Synced")
                Divider()
                ValueRow("Version", version)
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionLabel("Proximity sharing")
            WalletCard(padding = PaddingValues(0.dp)) {
                ChoiceRow(
                    "Bluetooth role", listOf("Peripheral", "Central"), if (bleCentral) 1 else 0,
                ) { bleCentral = it == 1; ProximityPrefs.setBleCentral(context, bleCentral) }
                Divider()
                ChoiceRow(
                    "NFC handover", listOf("Static", "Negotiated"), if (nfcNegotiated) 1 else 0,
                ) { nfcNegotiated = it == 1; ProximityPrefs.setNfcNegotiated(context, nfcNegotiated) }
            }
            Text(
                "Peripheral + Static work with the widest range of readers. Change these only if a reader needs it.",
                style = MaterialTheme.typography.bodySmall, color = c.inkMuted,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionLabel("Developer")
            WalletCard(padding = PaddingValues(0.dp)) {
                NavRow("Debug log", onOpenDebug)
            }
        }
    }
}

/** A labelled row with a 2+ option segmented control on the right, for a small enumerated setting. */
@Composable
private fun ChoiceRow(label: String, options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val c = WalletTheme.colors
    Column(Modifier.fillMaxWidth().padding(16.dp, 12.dp)) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = c.ink)
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEachIndexed { i, opt ->
                val on = i == selected
                val shape = RoundedCornerShape(10.dp)
                Box(
                    Modifier.weight(1f).clip(shape)
                        .background(if (on) c.brand else c.screen)
                        .border(1.dp, if (on) c.brand else c.cardBorderStrong, shape)
                        .clickable { onSelect(i) }.padding(vertical = 9.dp),
                    contentAlignment = Alignment.Center,
                ) { Text(opt, style = MaterialTheme.typography.labelMedium, color = if (on) Color.White else c.inkBody) }
            }
        }
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val c = WalletTheme.colors
    Row(Modifier.fillMaxWidth().padding(16.dp, 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = c.ink, modifier = Modifier.weight(1f))
        Switch(
            checked = checked, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = c.brand),
        )
    }
}

@Composable
private fun ValueRow(label: String, value: String) {
    val c = WalletTheme.colors
    Row(Modifier.fillMaxWidth().padding(16.dp, 15.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = c.ink, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = c.inkMuted)
    }
}

@Composable
private fun NavRow(label: String, onClick: () -> Unit) {
    val c = WalletTheme.colors
    Row(Modifier.fillMaxWidth().clickable { onClick() }.padding(16.dp, 15.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = c.ink, modifier = Modifier.weight(1f))
        Icon(Icons.Filled.ChevronRight, null, tint = c.inkFaint)
    }
}

@Composable
private fun Divider() {
    Spacer(Modifier.fillMaxWidth().height(1.dp).background(WalletTheme.colors.divider))
}
