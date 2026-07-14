package com.hopae.eudi.demo.ui

import com.hopae.eudi.wallet.PresentationRequest
import com.hopae.eudi.wallet.PresentationSession

/** Holder-side inbound scan schemes (offer vs. presentation), used by the unified scan router. */
internal val OFFER_SCHEMES = setOf("openid-credential-offer", "haip-vci")
internal val VP_SCHEMES = setOf("openid4vp", "eudi-openid4vp", "mdoc-openid4vp", "haip-vp")

/** A resolved presentation request paired with its live session, awaiting the user's consent decision. */
internal class PendingConsent(val session: PresentationSession, val request: PresentationRequest)
