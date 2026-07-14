package com.hopae.eudi.demo

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.hopae.eudi.demo.adapters.LogWalletLogger
import com.hopae.eudi.demo.security.AppLock
import com.hopae.eudi.demo.security.WalletSecurity
import com.hopae.eudi.demo.ui.WalletRoot
import com.hopae.eudi.demo.ui.screens.LockScreen
import com.hopae.eudi.demo.ui.screens.OnboardingScreen
import com.hopae.eudi.demo.ui.theme.WalletTheme
import com.hopae.eudi.wallet.Wallet
import com.hopae.eudi.wallet.android.dcapi.DcApiBranding
import com.hopae.eudi.wallet.android.dcapi.DcApiRegistrar
import java.io.ByteArrayOutputStream

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleIntentLink(intent)
        // Brand the DC API selector entries with this wallet's own launcher icon (scaled by the library).
        val branding = DcApiBranding(logoPng = appIconPng())
        val logger = LogWalletLogger()
        setContent {
            WalletTheme {
                Surface {
                    val ctx = LocalContext.current
                    var onboarded by remember { mutableStateOf(WalletSecurity.isOnboarded(ctx)) }
                    var locked by remember { mutableStateOf(onboarded) } // cold start: require unlock if set up

                    // Re-lock when the wallet returns to the foreground after being backgrounded — but not when
                    // it comes back from one of its own sub-activities (scanner / browser / Credential Manager).
                    val owner = LocalLifecycleOwner.current
                    DisposableEffect(owner) {
                        val obs = LifecycleEventObserver { _, event ->
                            if (event == Lifecycle.Event.ON_START && onboarded) {
                                if (AppLock.suppressNextResumeLock) AppLock.suppressNextResumeLock = false
                                else locked = true
                            }
                        }
                        owner.lifecycle.addObserver(obs)
                        onDispose { owner.lifecycle.removeObserver(obs) }
                    }

                    when {
                        !onboarded -> OnboardingScreen(activity = this@MainActivity, onDone = { onboarded = true; locked = false })
                        locked -> LockScreen(activity = this@MainActivity, onUnlock = { locked = false })
                        else -> WalletHost(branding, logger)
                    }
                }
            }
        }
    }

    @Composable
    private fun WalletHost(branding: DcApiBranding, logger: LogWalletLogger) {
        // The wallet assembles asynchronously (it fetches trust anchors from the trusted lists on first
        // launch, cached thereafter) — show a splash until it is ready.
        val wallet by produceState<Wallet?>(null) { value = DemoWallet.get(applicationContext) }
        when (val w = wallet) {
            null -> AssemblingSplash()
            else -> {
                LaunchedEffect(w) {
                    // Register credentials with the Credential Manager (DC API) + keep in sync.
                    DcApiRegistrar.register(this@MainActivity, w, branding, logger = logger)
                    w.credentials.changes.collect { DcApiRegistrar.register(this@MainActivity, w, branding, logger = logger) }
                }
                WalletRoot(w)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntentLink(intent)
    }

    /**
     * Routes an incoming deep link: the authorization-code redirect resumes the parked issuance session;
     * an offer / presentation link (haip-vci, haip-vp, openid-credential-offer, …) is handed to the UI.
     */
    private fun handleIntentLink(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme == "eu.europa.ec.euidi") PendingAuth.complete(data.toString())
        else IncomingLink.post(data.toString())
    }

    @Composable
    private fun AssemblingSplash() {
        Column(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator()
            Text("Assembling wallet…", modifier = Modifier.padding(top = 16.dp), style = MaterialTheme.typography.bodyMedium)
        }
    }

    /** This wallet's own launcher icon as PNG bytes — used as the DC API selector branding for its credentials. */
    private fun appIconPng(): ByteArray? = runCatching {
        val d = packageManager.getApplicationIcon(packageName)
        val bmp = Bitmap.createBitmap(d.intrinsicWidth.coerceAtLeast(1), d.intrinsicHeight.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        Canvas(bmp).also { d.setBounds(0, 0, it.width, it.height); d.draw(it) }
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }.getOrNull()
}
