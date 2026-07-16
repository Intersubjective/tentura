/// Authentication/session boundary exposed to the shared attention slice.
abstract interface class AttentionAccountPort {
  Stream<String> get currentAccountChanges;
}
