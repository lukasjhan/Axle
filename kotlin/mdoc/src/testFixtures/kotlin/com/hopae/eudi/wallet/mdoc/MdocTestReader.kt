package com.hopae.eudi.wallet.mdoc

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.spi.KeyInfo
import com.hopae.eudi.wallet.spi.SecureArea
import com.hopae.eudi.wallet.spi.SecureAreaCoseSigner
import com.hopae.eudi.wallet.spi.SigningAlgorithm

/** Builds a signed mdoc `DeviceRequest` for tests via the production [MdocReader] (the reader side). */
object MdocTestReader {

    suspend fun deviceRequest(
        area: SecureArea,
        readerKey: KeyInfo,
        docType: String,
        requested: Map<String, List<String>>,
        sessionTranscript: Cbor,
        x5chain: List<ByteArray>,
        intentToRetain: Boolean = false,
    ): ByteArray {
        val reader = MdocReader(ReaderAuthSigner(SecureAreaCoseSigner(area, readerKey.handle, SigningAlgorithm.ES256), x5chain))
        return reader.buildDeviceRequest(listOf(RequestedDocument(docType, requested, intentToRetain)), sessionTranscript)
    }
}
