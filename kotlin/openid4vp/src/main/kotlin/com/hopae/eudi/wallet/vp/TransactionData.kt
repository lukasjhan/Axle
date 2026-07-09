package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.sdjwt.JsonValue

/**
 * One parsed OpenID4VP `transaction_data` object (§8.4 / §5.1). [raw] is the original base64url string —
 * the hash bound into the KB-JWT (`transaction_data_hashes`, B.3.3.1) is computed over it verbatim, without
 * base64url-decoding first.
 */
class TransactionData(
    val raw: String,
    val type: String,
    /** DCQL credential-query ids that can authorize this transaction; the wallet binds it to exactly one (§5.1). */
    val credentialIds: List<String>,
    /** Allowed hash algorithms (`transaction_data_hashes_alg`); null → the default `sha-256` (B.3.3.1). */
    val hashAlgorithms: List<String>?,
) {
    companion object {
        /** Parses a base64url-encoded transaction_data string; throws [VpException.InvalidTransactionData] if malformed. */
        fun parse(raw: String): TransactionData {
            val obj = runCatching { JsonValue.parse(Base64Url.decodeToString(raw)) as? JsonValue.Obj }.getOrNull()
                ?: throw VpException.InvalidTransactionData("entry is not a base64url-encoded JSON object")
            val type = (obj["type"] as? JsonValue.Str)?.value
                ?: throw VpException.InvalidTransactionData("entry is missing a string 'type'")
            val ids = (obj["credential_ids"] as? JsonValue.Arr)?.items?.mapNotNull { (it as? JsonValue.Str)?.value }
            if (ids.isNullOrEmpty()) throw VpException.InvalidTransactionData("entry is missing a non-empty 'credential_ids'")
            val algs = (obj["transaction_data_hashes_alg"] as? JsonValue.Arr)?.items?.mapNotNull { (it as? JsonValue.Str)?.value }
            return TransactionData(raw, type, ids, algs?.ifEmpty { null })
        }
    }
}
