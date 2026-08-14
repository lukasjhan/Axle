import CborCose

/// ISO/IEC 18013-5 §7.2.5 — "Age attestation: nearest 'true' attestation above request".
///
/// An `age_over_NN` request does not mean "give me that exact element". It means *"provide the nearest age
/// attestation equal to or larger than NN with value TRUE, or smaller than NN with value FALSE"*, and the spec
/// fixes the selection logic: an mdoc asked for `age_over_18` while holding `age_over_21: true` answers
/// `age_over_21`, because that still answers the question and discloses less than a birth date would.
///
/// Without this, a wallet silently omits `age_over_18` it could have answered, and the verifier's most likely
/// next move — per the spec's own NOTE — is to ask for `birth_date` instead. The rule exists to keep that from
/// happening, so skipping it costs privacy rather than saving it.
///
/// Resolution stays inside one namespace: an mDL substitutes from the mDL's own age attestations, never from
/// another credential's.
public enum AgeAttestation {

    private static let prefix = "age_over_"

    /// §7.2.5's cap on `age_over_NN` elements per document request.
    public static let maxRequested = 2

    /// The `NN` of an `age_over_NN` identifier (00-99 per §7.2.5), or nil if this is not an age attestation.
    public static func age(of elementIdentifier: String) -> Int? {
        guard elementIdentifier.hasPrefix(prefix) else { return nil }
        let nn = elementIdentifier.dropFirst(prefix.count)
        guard nn.count == 2, nn.allSatisfy(\.isNumber) else { return nil }
        return Int(nn)
    }

    /// The element identifier that answers a request for `age_over_<requestedAge>` given the `held` elements of
    /// one namespace, or nil when §7.2.5 step 3 applies ("no age_over_nn data element shall be returned").
    ///
    /// Implements the three steps literally:
    /// 1. among the TRUE attestations with `nn >= NN`, the one with the smallest `nn - NN`;
    /// 2. otherwise, among the FALSE attestations with `nn <= NN`, the one with the smallest `NN - nn`;
    /// 3. otherwise nothing.
    ///
    /// An exact hit needs no special case — it is simply the difference-0 winner of step 1 or step 2.
    public static func resolve(requestedAge: Int, held: [String: Cbor]) -> String? {
        let attestations: [(id: String, age: Int, value: Bool)] = held.compactMap { id, value in
            guard let age = age(of: id), case let .bool(b) = value else { return nil } // non-boolean ⇒ not an attestation
            return (id, age, b)
        }
        if let hit = attestations.filter({ $0.value && $0.age >= requestedAge })
            .min(by: { $0.age - requestedAge < $1.age - requestedAge }) {
            return hit.id
        }
        return attestations.filter { !$0.value && $0.age <= requestedAge }
            .min(by: { requestedAge - $0.age < requestedAge - $1.age })?.id
    }

    /// How many `age_over_NN` elements `elementIdentifiers` asks for. §7.2.5: "an mDL reader **shall not**
    /// request more than two age_over_NN data elements" during a single data retrieval phase — asking for a
    /// ladder of them (16/18/21/25) narrows the holder's age far past what any one question needs.
    public static func requestedCount<S: Sequence>(_ elementIdentifiers: S) -> Int where S.Element == String {
        elementIdentifiers.reduce(0) { $0 + (age(of: $1) == nil ? 0 : 1) }
    }
}
