import CborCose

/// The device-signed data element that carries one mdoc transaction_data entry (ISO 18013-7 B.2.1). A
/// transaction data *type* defines the (namespace, elementId) and how `value` is computed — that mapping is
/// type-specific and lives outside this SDK, so it is supplied by the host via `MdocTransactionDataBinder`.
public struct DeviceSignedTransactionData: Sendable {
    public let namespace: String
    public let elementId: String
    public let value: Cbor
    public init(namespace: String, elementId: String, value: Cbor) {
        self.namespace = namespace; self.elementId = elementId; self.value = value
    }
}

/// Host-provided mapping from a parsed `transaction_data` entry to the mdoc data element that protects it,
/// for the credential formats that carry it via mdoc authentication (B.2.1). Returns nil when the host does
/// not support the entry's `type` for mdoc — the wallet then rejects with `invalid_transaction_data`. The
/// wallet still enforces that the returned element is authorized in the MSO `keyAuthorizations` (§9.1.2.4).
public typealias MdocTransactionDataBinder = @Sendable (TransactionData) -> DeviceSignedTransactionData?
