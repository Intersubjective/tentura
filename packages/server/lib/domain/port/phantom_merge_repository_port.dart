import 'owner_graph_transaction_port.dart';

enum PhantomMergeOrigin {
  inviteNew(1),
  inviteExisting(2),
  manualLink(3);

  const PhantomMergeOrigin(this.code);

  final int code;

  static PhantomMergeOrigin fromCode(int code) => values.firstWhere(
    (origin) => origin.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'origin', 'Unknown merge origin'),
  );
}

typedef PhantomMergeTarget = ({
  String ownerId,
  String phantomId,
  String userId,
});

abstract interface class PhantomMergeRepositoryPort {
  /// Locks the owner's active entry and returns its current name.
  Future<String?> lockActive(OwnerGraphScope scope, PhantomMergeTarget target);

  /// Persists the guarded merge, its undo record and owner attention event.
  Future<String> merge(
    OwnerGraphScope scope,
    PhantomMergeTarget target, {
    required PhantomMergeOrigin origin,
    required String displayName,
  });
}
