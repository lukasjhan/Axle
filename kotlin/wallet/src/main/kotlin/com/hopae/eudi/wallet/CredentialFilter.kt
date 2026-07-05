package com.hopae.eudi.wallet

import com.hopae.eudi.wallet.spi.CredentialFormat

/** Local (non-network) predicate over stored credentials. For DCQL semantics use `credentials.match`. */
sealed interface CredentialFilter {
    fun matches(credential: Credential): Boolean

    data object All : CredentialFilter {
        override fun matches(credential: Credential): Boolean = true
    }

    data class ByVct(val vct: String) : CredentialFilter {
        override fun matches(credential: Credential): Boolean =
            (credential.format as? CredentialFormat.SdJwtVc)?.vct == vct
    }

    data class ByDocType(val docType: String) : CredentialFilter {
        override fun matches(credential: Credential): Boolean =
            (credential.format as? CredentialFormat.MsoMdoc)?.docType == docType
    }

    companion object {
        val all: CredentialFilter = All
        fun byVct(vct: String): CredentialFilter = ByVct(vct)
        fun byDocType(docType: String): CredentialFilter = ByDocType(docType)
    }
}
