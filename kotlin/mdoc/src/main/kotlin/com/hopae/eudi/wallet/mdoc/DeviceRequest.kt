package com.hopae.eudi.wallet.mdoc

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.CborDecoder
import com.hopae.eudi.wallet.cbor.CborEncoder
import com.hopae.eudi.wallet.cbor.cose.CoseSign1
import com.hopae.eudi.wallet.cbor.cose.EcPublicKey

/** A data element a reader asks for (ISO 18013-5 §8.3.2.1.2.1). */
class RequestedElement(val identifier: String, val intentToRetain: Boolean)

/** One document request: the requested docType + elements, plus the reader's optional signature. */
class DocRequest(
    val docType: String,
    /** namespace -> requested elements. */
    val requested: Map<String, List<RequestedElement>>,
    /** The `ItemsRequestBytes` (#6.24) as received — needed to reconstruct `ReaderAuthentication`. */
    val itemsRequestBytes: Cbor,
    val readerAuth: CoseSign1?,
) {
    /**
     * The requested elements flagged `IntentToRetain` (ISO 18013-5 §8.3.2.1.2.1): namespace -> element
     * identifiers the reader declared it will keep beyond the transaction. Namespaces with nothing retained
     * are omitted. Surfaced so a holder can put the declaration in front of the user before consenting.
     */
    fun retained(): Map<String, List<String>> =
        requested.mapValues { (_, elems) -> elems.filter { it.intentToRetain }.map { it.identifier } }
            .filterValues { it.isNotEmpty() }

    /**
     * The element identifiers to disclose from [issuerSigned] for this request: the requested elements the
     * mdoc actually holds, with `age_over_NN` resolved per [AgeAttestation] (ISO 18013-5 §7.2.5) rather than
     * matched literally — so `age_over_18` can be answered by a held `age_over_21: true`, and a held
     * `age_over_16: true` does *not* answer it.
     */
    fun disclosable(issuerSigned: IssuerSigned): Map<String, List<String>> {
        val held = issuerSigned.elements()
        return requested.mapValues { (ns, elems) ->
            val heldNs = held[ns].orEmpty()
            elems.mapNotNull { element ->
                val age = AgeAttestation.ageOf(element.identifier)
                // §7.2.5 governs age attestations; everything else is a literal "do you hold this element".
                // A malformed attestation (non-boolean value) falls back to the literal match.
                if (age != null) AgeAttestation.resolve(age, heldNs) ?: element.identifier.takeIf { it in heldNs }
                else element.identifier.takeIf { it in heldNs }
            }.distinct() // two age_over_NN requests can resolve to the same attestation
        }.filterValues { it.isNotEmpty() }
    }
}

/** A reader's `DeviceRequest` (ISO 18013-5 §8.3.2.1.2.1): the documents + elements it wants. */
class DeviceRequest(val version: String, val docRequests: List<DocRequest>) {

    fun docRequestFor(docType: String): DocRequest? = docRequests.firstOrNull { it.docType == docType }

    companion object {
        fun decode(bytes: ByteArray): DeviceRequest {
            val map = CborDecoder.decode(bytes) as? Cbor.CborMap ?: throw MdocException("DeviceRequest must be a map")
            val version = (map.field("version") as? Cbor.Text)?.value ?: throw MdocException("missing version")
            val docRequests = (map.field("docRequests") as? Cbor.Array ?: throw MdocException("missing docRequests")).items.map { dr ->
                val drMap = dr as? Cbor.CborMap ?: throw MdocException("docRequest must be a map")
                val itemsRequestTagged = drMap.field("itemsRequest") as? Cbor.Tagged ?: throw MdocException("missing itemsRequest")
                val inner = (itemsRequestTagged.value as? Cbor.Bytes)?.value ?: throw MdocException("itemsRequest must be #6.24 bstr")
                val itemsRequest = CborDecoder.decode(inner) as? Cbor.CborMap ?: throw MdocException("ItemsRequest must be a map")
                val docType = (itemsRequest.field("docType") as? Cbor.Text)?.value ?: throw MdocException("missing docType")
                val nsMap = itemsRequest.field("nameSpaces") as? Cbor.CborMap ?: throw MdocException("missing nameSpaces")
                val requested = nsMap.entries.associate { (nsKey, elems) ->
                    val ns = (nsKey as? Cbor.Text)?.value ?: throw MdocException("namespace must be text")
                    ns to (elems as? Cbor.CborMap ?: throw MdocException("elements must be a map")).entries.map { (el, intent) ->
                        RequestedElement((el as? Cbor.Text)?.value ?: throw MdocException("element id must be text"), (intent as? Cbor.Bool)?.value ?: false)
                    }
                }
                val readerAuth = drMap.field("readerAuth")?.let { CoseSign1.fromCbor(it) }
                DocRequest(docType, requested, itemsRequestTagged, readerAuth)
            }
            return DeviceRequest(version, docRequests)
        }

        private fun Cbor.CborMap.field(name: String): Cbor? =
            entries.firstOrNull { (k, _) -> (k as? Cbor.Text)?.value == name }?.second
    }
}

/** Resolves + trusts a reader's key from the `readerAuth` x5chain (implemented by the `trust` module). */
fun interface MdocReaderTrust {
    suspend fun readerKey(x5chain: List<ByteArray>): EcPublicKey
}

/** Outcome of reader authentication (ISO 18013-5 §9.1.4). */
class ReaderInfo(val trusted: Boolean, val certificateChain: List<ByteArray>?)

/**
 * Verifies a reader's `readerAuth` (ISO 18013-5 §9.1.4): a COSE_Sign1 over
 * `ReaderAuthentication = ["ReaderAuthentication", SessionTranscript, ItemsRequestBytes]`
 * (detached payload). Confirms the reader owns the presented certificate chain, which the
 * [trust] validates to a reader trust anchor — this authenticates *who is asking*.
 */
object ReaderAuth {

    suspend fun verify(docRequest: DocRequest, sessionTranscript: Cbor, trust: MdocReaderTrust): ReaderInfo {
        val readerAuth = docRequest.readerAuth ?: throw MdocException("docRequest has no readerAuth")
        val x5chain = readerAuth.protected.x5chain ?: readerAuth.unprotected.x5chain
            ?: throw MdocException("readerAuth has no x5chain")
        val key = trust.readerKey(x5chain) // validates the reader chain (throws if untrusted)

        val readerAuthentication = Cbor.Array(listOf(Cbor.Text("ReaderAuthentication"), sessionTranscript, docRequest.itemsRequestBytes))
        val readerAuthBytes = CborEncoder.encode(Cbor.Tagged(TAG_ENCODED_CBOR, Cbor.Bytes(CborEncoder.encode(readerAuthentication))))
        if (!readerAuth.verify(key, detachedPayload = readerAuthBytes)) throw MdocException("readerAuth signature invalid")

        return ReaderInfo(trusted = true, certificateChain = x5chain)
    }
}
