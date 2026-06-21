
/// Local My Work desk UI preferences (implemented in the data layer).
abstract class MyWorkDeskPreferencesPort {
  Future<bool> isFinishedArchiveHintDismissed({required String userId});

  Future<void> setFinishedArchiveHintDismissed({required String userId});
}
