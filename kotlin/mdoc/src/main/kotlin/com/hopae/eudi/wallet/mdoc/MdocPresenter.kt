package com.hopae.eudi.wallet.mdoc

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.CborDecoder
import com.hopae.eudi.wallet.cbor.CborEncoder
import com.hopae.eudi.wallet.cbor.cose.CoseHeaders
import com.hopae.eudi.wallet.cbor.cose.CoseSign1
import com.hopae.eudi.wallet.cbor.cose.CoseSigner
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.spi.coseAlgorithm

/**
 * Builds an mdoc `DeviceResponse` (ISO 18013-5 §8.3.2.1.2.2) for presentation: keeps only the
 * disclosed issuer-signed items and produces `DeviceSigned` — a `deviceSignature` COSE_Sign1
 * over the `DeviceAuthentication` structure (detached payload) bound to the [sessionTranscript].
 */
object MdocPresenter {

    suspend fun deviceResponse(
        issuerSigned: IssuerSigned,
        docType: String,
        /** namespace -> element identifiers to disclose. */
        disclosed: Map<String, List<String>>,
        sessionTranscript: Cbor,
        deviceSigner: CoseSigner,
        deviceSignAlgorithm: SigningAlgorithm = SigningAlgorithm.ES256,
    ): ByteArray {
        // Keep only the disclosed items, re-emitting their exact IssuerSignedItemBytes (#6.24).
        val filteredNs = issuerSigned.nameSpaces.mapNotNull { (ns, items) ->
            val ids = disclosed[ns] ?: return@mapNotNull null
            val kept = items.filter { it.item.elementIdentifier in ids }
            if (kept.isEmpty()) null else Cbor.Text(ns) to Cbor.Array(kept.map { CborDecoder.decode(it.itemBytes) })
        }
        val issuerSignedCbor = Cbor.CborMap(
            listOf(
                Cbor.Text("nameSpaces") to Cbor.CborMap(filteredNs),
                Cbor.Text("issuerAuth") to issuerSigned.issuerAuth.toCbor(tagged = false),
            )
        )

        // DeviceNameSpaces is empty for a basic presentation (no device-signed data elements).
        val deviceNameSpacesBytes = Cbor.Tagged(TAG_ENCODED_CBOR, Cbor.Bytes(CborEncoder.encode(Cbor.CborMap(emptyList()))))

        // DeviceAuthentication = ["DeviceAuthentication", SessionTranscript, DocType, DeviceNameSpacesBytes]
        val deviceAuth = Cbor.Array(listOf(Cbor.Text("DeviceAuthentication"), sessionTranscript, Cbor.Text(docType), deviceNameSpacesBytes))
        val deviceAuthBytes = CborEncoder.encode(Cbor.Tagged(TAG_ENCODED_CBOR, Cbor.Bytes(CborEncoder.encode(deviceAuth))))

        val deviceSignature = CoseSign1.sign(
            protected = CoseHeaders.of(algorithm = deviceSignAlgorithm.coseAlgorithm),
            payload = null,
            detachedPayload = deviceAuthBytes,
            signer = deviceSigner,
        )

        val deviceSigned = Cbor.CborMap(
            listOf(
                Cbor.Text("nameSpaces") to deviceNameSpacesBytes,
                Cbor.Text("deviceAuth") to Cbor.CborMap(listOf(Cbor.Text("deviceSignature") to deviceSignature.toCbor(tagged = false))),
            )
        )

        val document = Cbor.CborMap(
            listOf(
                Cbor.Text("docType") to Cbor.Text(docType),
                Cbor.Text("issuerSigned") to issuerSignedCbor,
                Cbor.Text("deviceSigned") to deviceSigned,
            )
        )
        val deviceResponse = Cbor.CborMap(
            listOf(
                Cbor.Text("version") to Cbor.Text("1.0"),
                Cbor.Text("documents") to Cbor.Array(listOf(document)),
                Cbor.Text("status") to Cbor.int(0),
            )
        )
        return CborEncoder.encode(deviceResponse)
    }
}
