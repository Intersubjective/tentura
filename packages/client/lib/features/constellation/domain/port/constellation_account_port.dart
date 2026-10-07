/// Authentication/session boundary exposed to the constellation slice.
abstract interface class ConstellationAccountPort {
  Stream<String> get currentAccountChanges;
}
