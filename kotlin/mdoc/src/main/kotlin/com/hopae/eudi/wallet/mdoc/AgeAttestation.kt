package com.hopae.eudi.wallet.mdoc

import com.hopae.eudi.wallet.cbor.Cbor

/**
 * ISO/IEC 18013-5 §7.2.5 — "Age attestation: nearest 'true' attestation above request".
 *
 * An `age_over_NN` request does not mean "give me that exact element". It means *"provide the nearest age
 * attestation equal to or larger than NN with value TRUE, or smaller than NN with value FALSE"*, and the spec
 * fixes the selection logic: an mdoc asked for `age_over_18` while holding `age_over_21: true` answers
 * `age_over_21`, because that still answers the question and discloses less than a birth date would.
 *
 * Without this, a wallet silently omits `age_over_18` it could have answered, and the verifier's most likely
 * next move — per the spec's own NOTE — is to ask for `birth_date` instead. The rule exists to keep that from
 * happening, so skipping it costs privacy rather than saving it.
 *
 * Resolution stays inside one namespace: an mDL substitutes from the mDL's own age attestations, never from
 * another credential's.
 */
object AgeAttestation {

    private const val PREFIX = "age_over_"

    /** The `NN` of an `age_over_NN` identifier (00-99 per §7.2.5), or null if this is not an age attestation. */
    fun ageOf(elementIdentifier: String): Int? {
        if (!elementIdentifier.startsWith(PREFIX)) return null
        val nn = elementIdentifier.removePrefix(PREFIX)
        if (nn.length != 2 || !nn.all { it.isDigit() }) return null
        return nn.toInt()
    }

    /**
     * The element identifier that answers a request for `age_over_[requestedAge]` given the [held] elements of
     * one namespace, or null when §7.2.5 step 3 applies ("no age_over_nn data element shall be returned").
     *
     * Implements the three steps literally:
     * 1. among the TRUE attestations with `nn >= NN`, the one with the smallest `nn - NN`;
     * 2. otherwise, among the FALSE attestations with `nn <= NN`, the one with the smallest `NN - nn`;
     * 3. otherwise nothing.
     *
     * An exact hit needs no special case — it is simply the difference-0 winner of step 1 or step 2.
     */
    fun resolve(requestedAge: Int, held: Map<String, Cbor>): String? {
        val attestations = held.mapNotNull { (id, value) ->
            val age = ageOf(id) ?: return@mapNotNull null
            val bool = (value as? Cbor.Bool)?.value ?: return@mapNotNull null // a non-boolean is not an attestation
            Triple(id, age, bool)
        }
        return attestations.filter { (_, age, value) -> value && age >= requestedAge }
            .minByOrNull { (_, age, _) -> age - requestedAge }?.first
            ?: attestations.filter { (_, age, value) -> !value && age <= requestedAge }
                .minByOrNull { (_, age, _) -> requestedAge - age }?.first
    }

    /**
     * How many `age_over_NN` elements [elementIdentifiers] asks for. §7.2.5: "an mDL reader **shall not**
     * request more than two age_over_NN data elements" during a single data retrieval phase — asking for a
     * ladder of them (16/18/21/25) narrows the holder's age far past what any one question needs.
     */
    fun requestedCount(elementIdentifiers: Iterable<String>): Int = elementIdentifiers.count { ageOf(it) != null }

    /** §7.2.5's cap on `age_over_NN` elements per document request. */
    const val MAX_REQUESTED = 2
}
