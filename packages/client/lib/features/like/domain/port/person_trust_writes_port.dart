/// One acknowledged trust write of the signed-in account: the server stored
/// `amount` as the account's vote for `personId`.
typedef PersonTrustWrite = ({String personId, int amount});

/// The account's acknowledged trust writes, wherever they were made (People,
/// profile, the trust graph or the field), so a projection that shows the
/// account's own trust can follow it without a read (#672).
abstract interface class PersonTrustWritesPort {
  Stream<PersonTrustWrite> get personTrustWrites;
}
