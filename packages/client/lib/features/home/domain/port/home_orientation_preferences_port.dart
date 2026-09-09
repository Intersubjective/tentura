import '../entity/home_activation.dart';

/// Local first-run orientation preferences (implemented in the data layer).
abstract class HomeOrientationPreferencesPort {
  Future<bool> isActivated({required String userId});

  Future<void> setActivated({required String userId});

  Future<bool> isOrientationDismissed({required String userId});

  Future<void> setOrientationDismissed({required String userId});

  Future<void> resetFirstRunState({required String userId});

  Future<OrientationDebugOverride> getDebugOverride();

  Future<void> setDebugOverride(OrientationDebugOverride value);
}
