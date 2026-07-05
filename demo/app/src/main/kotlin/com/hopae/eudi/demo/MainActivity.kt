package com.hopae.eudi.demo

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.lifecycle.lifecycleScope
import com.hopae.eudi.demo.ui.WalletApp
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val wallet = DemoWallet.get(this)
        handleIntentLink(intent)
        // Register credentials with the Credential Manager (Digital Credentials API) + keep in sync.
        lifecycleScope.launch {
            DcApiRegistrar.register(this@MainActivity, wallet)
            wallet.credentials.changes.collect { DcApiRegistrar.register(this@MainActivity, wallet) }
        }
        setContent {
            MaterialTheme {
                Surface { WalletApp(wallet) }
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
}
