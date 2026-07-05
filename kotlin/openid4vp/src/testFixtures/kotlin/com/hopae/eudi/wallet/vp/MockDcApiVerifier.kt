package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.CborDecoder
import com.hopae.eudi.wallet.cbor.CborEncoder
import com.hopae.eudi.wallet.cbor.cose.CoseSign1
import com.hopae.eudi.wallet.mdoc.IssuerSigned
import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.sdjwt.JsonValue

/**
 * A mock Digital Credentials API verifier for mdoc: builds the request object handed to the wallet by
 * the platform (no HTTP) and verifies the returned response — device signature over the origin-bound
 * DC API SessionTranscript, using the deviceKey from the MSO.
 */
class MockDcApiVerifier(
    val docType: String = "org.iso.18013.5.1.mDL",
    val namespace: String = "org.iso.18013.5.1",
    val origin: String = "https://verifier.example",
    val nonce: String = "dcapi-nonce",
) {
    fun requestObject(): String =
        """{"response_type":"vp_token","response_mode":"dc_api","nonce":"$nonce",""" +
            """"dcql_query":{"credentials":[{"id":"query_0","format":"mso_mdoc","meta":{"doctype_value":"$docType"},""" +
            """"claims":[{"path":["$namespace","family_name"]},{"path":["$namespace","given_name"]}]}]}}"""

    /** Verifies the DC API response object and returns the disclosed element identifiers. */
    fun verify(responseJson: String): Set<String> {
        val response = JsonValue.parse(responseJson) as JsonValue.Obj
        val vpToken = response["vp_token"] as JsonValue.Obj
        val presentation = ((vpToken["query_0"] as JsonValue.Arr).items.first() as JsonValue.Str).value
        val deviceResponse = CborDecoder.decode(Base64Url.decode(presentation))
        val document = (map(deviceResponse, "documents") as Cbor.Array).items.single()
        val issuerSigned = IssuerSigned.fromCbor(map(document, "issuerSigned")!!)
        val deviceKey = issuerSigned.parseMso().deviceKey

        val deviceSigned = map(document, "deviceSigned")!!
        val deviceSignature = CoseSign1.fromCbor(map(map(deviceSigned, "deviceAuth")!!, "deviceSignature")!!)
        val sessionTranscript = Oid4vpSessionTranscript.dcApi(origin, nonce, null)
        val deviceNameSpacesBytes = map(deviceSigned, "nameSpaces")!!
        val deviceAuth = Cbor.Array(listOf(Cbor.Text("DeviceAuthentication"), sessionTranscript, Cbor.Text(docType), deviceNameSpacesBytes))
        val deviceAuthBytes = CborEncoder.encode(Cbor.Tagged(24u, Cbor.Bytes(CborEncoder.encode(deviceAuth))))
        require(deviceSignature.verify(deviceKey, detachedPayload = deviceAuthBytes)) { "device signature must bind the DC API origin" }

        return issuerSigned.nameSpaces[namespace]!!.map { it.item.elementIdentifier }.toSet()
    }

    private fun map(c: Cbor, key: String): Cbor? =
        (c as Cbor.CborMap).entries.firstOrNull { (k, _) -> (k as? Cbor.Text)?.value == key }?.second
}
