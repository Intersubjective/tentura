import 'package:tentura/features/my_work/data/repository/my_work_desk_preferences_repository.dart'
    show MyWorkDeskPreferencesRepository;

/// Local My Work desk UI preferences (implemented in the data layer).
abstract class MyWorkDeskPreferencesPort {
  Future<bool> isFinishedArchiveHintDismissed({required String userId});

  Future<void> setFinishedArchiveHintDismissed({required String userId});
}
