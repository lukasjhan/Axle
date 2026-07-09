package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.cbor.Cbor

/**
 * The device-signed data element that carries one mdoc transaction_data entry (ISO 18013-7 B.2.1). A
 * transaction data *type* defines the (namespace, elementId) and how [value] is computed — that mapping is
 * type-specific and lives outside this SDK, so it is supplied by the host via [MdocTransactionDataBinder].
 */
class DeviceSignedTransactionData(val namespace: String, val elementId: String, val value: Cbor)

/**
 * Host-provided mapping from a parsed `transaction_data` entry to the mdoc data element that protects it,
 * for the credential formats that carry it via mdoc authentication (B.2.1). Returns null when the host does
 * not support the entry's `type` for mdoc — the wallet then rejects with `invalid_transaction_data`.
 *
 * The wallet still enforces that the returned element is authorized in the MSO `keyAuthorizations` (§9.1.2.4)
 * before device-signing it; the host only decides *what* element represents the transaction.
 */
fun interface MdocTransactionDataBinder {
    fun bind(transactionData: TransactionData): DeviceSignedTransactionData?
}
