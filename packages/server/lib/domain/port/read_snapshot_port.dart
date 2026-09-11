// Domain-owned read snapshot boundary without importing the database layer.
// ignore: one_member_abstracts
abstract interface class ReadSnapshotPort {
  Future<T> withReadSnapshot<T>(Future<T> Function() action);
}
