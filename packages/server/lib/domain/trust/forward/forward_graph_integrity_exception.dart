/// Thrown when the eligible forward DAG has a cycle or exceeds depth bounds.
final class ForwardGraphIntegrityException implements Exception {
  const ForwardGraphIntegrityException(this.committerId);

  final String committerId;

  @override
  String toString() =>
      'ForwardGraphIntegrityException(committer=$committerId)';
}
