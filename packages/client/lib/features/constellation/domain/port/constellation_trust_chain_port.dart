import '../entity/constellation_trust_chain_person.dart';

// ignore: one_member_abstracts -- narrow read boundary, like the field port
abstract interface class ConstellationTrustChainPort {
  /// The shortest chain of explicit trust from the viewer to [personId],
  /// viewer first and [personId] last; empty when the viewer may see none.
  /// Fetched lazily when the field shows no chain to the selected person.
  Future<List<ConstellationTrustChainPerson>> fetchTrustChain(String personId);
}
