// ignore: one_member_abstracts -- narrow read boundary, like the field port
abstract interface class ConstellationMutualTrustPort {
  /// Ids of the people [personId] trusts both ways (explicit trust marks
  /// only), among those the viewer may see; the viewer is included when
  /// that is so. Fetched lazily when [personId] is selected on the field.
  Future<Set<String>> fetchMutualTrust(String personId);
}
