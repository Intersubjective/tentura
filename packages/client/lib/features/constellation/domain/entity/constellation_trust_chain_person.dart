/// One person on the server's trust chain to a selected person: the id and
/// the name to show, whether or not they are on the field.
final class ConstellationTrustChainPerson {
  const ConstellationTrustChainPerson({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}
