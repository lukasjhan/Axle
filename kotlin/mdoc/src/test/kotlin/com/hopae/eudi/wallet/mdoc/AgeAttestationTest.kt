package com.hopae.eudi.wallet.mdoc

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/** ISO/IEC 18013-5 §7.2.5 — "Age attestation: nearest 'true' attestation above request". */
class AgeAttestationTest {

    private val docType = "org.iso.18013.5.1.mDL"
    private val namespace = "org.iso.18013.5.1"

    private fun held(vararg attestations: Pair<Int, Boolean>): Map<String, Cbor> =
        attestations.associate { (age, value) -> "age_over_%02d".format(age) to Cbor.Bool(value) }

    @Test
    fun parsesTwoDigitIdentifiersOnly() {
        assertEquals(18, AgeAttestation.ageOf("age_over_18"))
        assertEquals(0, AgeAttestation.ageOf("age_over_00"))
        assertEquals(99, AgeAttestation.ageOf("age_over_99"))
        assertNull(AgeAttestation.ageOf("age_over_8")) // §7.2.5: NN is 00-99, two digits
        assertNull(AgeAttestation.ageOf("age_over_180"))
        assertNull(AgeAttestation.ageOf("age_over_ab"))
        assertNull(AgeAttestation.ageOf("age_in_years"))
        assertNull(AgeAttestation.ageOf("birth_date"))
    }

    /** Step 1: among TRUE attestations with nn >= NN, the smallest difference wins. */
    @Test
    fun step1PicksNearestTrueAtOrAboveRequest() {
        val mdl = held(16 to true, 18 to true, 21 to true, 25 to false)
        assertEquals("age_over_21", AgeAttestation.resolve(21, mdl))
        assertEquals("age_over_18", AgeAttestation.resolve(18, mdl))
        assertEquals("age_over_16", AgeAttestation.resolve(16, mdl))
        // Nothing held at exactly 20 — the nearest TRUE above it answers "are you over 20?" just as well.
        assertEquals("age_over_21", AgeAttestation.resolve(20, mdl))
        assertEquals("age_over_18", AgeAttestation.resolve(17, mdl))
    }

    /** Step 2: no TRUE at/above the request, so the nearest FALSE at/below it answers instead. */
    @Test
    fun step2FallsBackToNearestFalseAtOrBelowRequest() {
        val minor = held(13 to true, 16 to false, 18 to false, 21 to false)
        assertEquals("age_over_18", AgeAttestation.resolve(18, minor))
        assertEquals("age_over_16", AgeAttestation.resolve(17, minor)) // nearest FALSE <= 17
        assertEquals("age_over_18", AgeAttestation.resolve(20, minor))
        assertEquals("age_over_13", AgeAttestation.resolve(13, minor)) // TRUE exact hit wins step 1
    }

    /** Step 3: neither branch produces an answer, so no age element is returned at all. */
    @Test
    fun step3ReturnsNothingWhenNeitherBranchMatches() {
        // "over 25 is false" does not answer "are you over 18?" — and there is no TRUE at or above 18.
        assertNull(AgeAttestation.resolve(18, held(25 to false)))
        assertNull(AgeAttestation.resolve(18, emptyMap()))
        // A TRUE strictly below the request is not an answer either.
        assertNull(AgeAttestation.resolve(21, held(18 to true)))
    }

    /** Only booleans are attestations; a malformed value must not be picked as an answer. */
    @Test
    fun ignoresNonBooleanValues() {
        assertNull(AgeAttestation.resolve(18, mapOf("age_over_18" to Cbor.Text("true"))))
    }

    // ---- end-to-end through DocRequest.disclosable ----

    private class Fixture {
        val area = SoftwareSecureArea()
        val issuerKey = runBlocking { area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)) }
        val deviceKey = runBlocking { area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)) }
    }

    private fun mdoc(f: Fixture, elements: List<Pair<String, Cbor>>): IssuerSigned = runBlocking {
        IssuerSigned.decode(
            MdocTestIssuer.issue(
                area = f.area, issuerKey = f.issuerKey, deviceKey = f.deviceKey.publicKey,
                docType = docType, namespace = namespace, elements = elements,
                x5chain = listOf(byteArrayOf(0x30, 0x01)),
                signed = Instant.parse("2026-01-01T00:00:00Z"),
                validFrom = Instant.parse("2026-01-01T00:00:00Z"),
                validUntil = Instant.parse("2027-01-01T00:00:00Z"),
            ),
        )
    }

    private fun docRequest(vararg elements: String): DocRequest = DocRequest(
        docType = docType,
        requested = mapOf(namespace to elements.map { RequestedElement(it, intentToRetain = false) }),
        itemsRequestBytes = Cbor.Null,
        readerAuth = null,
    )

    /** A request the mdoc cannot answer literally is still answered by the nearest attestation above it. */
    @Test
    fun disclosableSubstitutesTheNearestAttestation() {
        val f = Fixture()
        val issuerSigned = mdoc(
            f,
            listOf(
                "family_name" to Cbor.Text("Han"),
                "age_over_18" to Cbor.Bool(true),
                "age_over_21" to Cbor.Bool(true),
            ),
        )
        // Asked for age_over_20, which this mDL does not carry — age_over_21: true answers it (§7.2.5 step 1).
        assertEquals(listOf("age_over_21"), docRequest("age_over_20").disclosable(issuerSigned)[namespace])
        assertEquals(listOf("family_name", "age_over_18"), docRequest("family_name", "age_over_18").disclosable(issuerSigned)[namespace])
    }

    /** Two requests resolving to the same attestation disclose it once, not twice. */
    @Test
    fun disclosableDeduplicatesResolvedAttestations() {
        val f = Fixture()
        val issuerSigned = mdoc(f, listOf("age_over_21" to Cbor.Bool(true)))
        assertEquals(listOf("age_over_21"), docRequest("age_over_18", "age_over_20").disclosable(issuerSigned)[namespace])
    }

    /** Step 3 through the request path: the namespace drops out rather than disclosing a wrong answer. */
    @Test
    fun disclosableOmitsUnanswerableAgeRequests() {
        val f = Fixture()
        val issuerSigned = mdoc(f, listOf("age_over_16" to Cbor.Bool(true)))
        assertNull(docRequest("age_over_21").disclosable(issuerSigned)[namespace])
    }

    /** Non-age elements keep their literal matching — substitution is scoped to age attestations. */
    @Test
    fun disclosableLeavesOtherElementsLiteral() {
        val f = Fixture()
        val issuerSigned = mdoc(f, listOf("family_name" to Cbor.Text("Han"), "age_over_18" to Cbor.Bool(true)))
        assertEquals(listOf("family_name"), docRequest("family_name", "given_name").disclosable(issuerSigned)[namespace])
    }

    /** §7.2.5: "an mDL reader shall not request more than two age_over_NN data elements". */
    @Test
    fun readerRejectsMoreThanTwoAgeRequests(): Unit = runBlocking {
        val reader = MdocReader()
        val ladder = RequestedDocument(docType, mapOf(namespace to listOf("age_over_16", "age_over_18", "age_over_21")))
        assertFailsWith<IllegalArgumentException> { reader.buildDeviceRequest(listOf(ladder), Cbor.Null) }

        // Two is the cap, not an error.
        val allowed = RequestedDocument(docType, mapOf(namespace to listOf("age_over_18", "age_over_21", "family_name")))
        reader.buildDeviceRequest(listOf(allowed), Cbor.Null)
    }
}
