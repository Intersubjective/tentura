import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/auth/domain/entity/auth_recovery_outcome.dart';
import 'package:tentura/features/auth/ui/bloc/auth_state.dart';
import 'package:tentura/features/auth/ui/widget/auth_recovery_listener.dart';

void main() {
  group('authRecoveryListenerShouldListen', () {
    final base = AuthState(updatedAt: DateTime.utc(2026));

    test('reacts to authRecoveryNeeded changes', () {
      final previous = base;
      final current = base.copyWith(authRecoveryNeeded: true);

      expect(authRecoveryListenerShouldListen(previous, current), isTrue);
    });

    test('reacts to authSessionLossCount changes', () {
      final previous = base;
      final current = base.copyWith(authSessionLossCount: 1);

      expect(authRecoveryListenerShouldListen(previous, current), isTrue);
    });

    test('reacts to pendingRecoveryNavigation changes', () {
      final previous = base;
      final current = base.copyWith(
        pendingRecoveryNavigation: AuthRecoveryNavigation.nativeLogin,
      );

      expect(authRecoveryListenerShouldListen(previous, current), isTrue);
    });
  });
}
