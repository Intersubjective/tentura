/// Browser «Leave site?» guard for editors with unpersisted work (#1059).
// ignore: one_member_abstracts -- injectable boundary with a test reset hook
abstract class UnsavedChangesGuardPort {
  void setDirty(Object owner, bool dirty);

  /// Clears all owners; for widget/integration test teardown only.
  void resetForTest();
}
