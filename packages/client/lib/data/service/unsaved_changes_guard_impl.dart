import 'package:injectable/injectable.dart';

import 'package:tentura/domain/port/unsaved_changes_guard_port.dart';

import 'unsaved_changes_guard.dart';

@Singleton(as: UnsavedChangesGuardPort)
class UnsavedChangesGuard implements UnsavedChangesGuardPort {
  @override
  void setDirty(Object owner, bool dirty) =>
      unsavedChangesGuardSetDirty(owner, dirty);

  @override
  void resetForTest() => unsavedChangesGuardResetForTest();
}
