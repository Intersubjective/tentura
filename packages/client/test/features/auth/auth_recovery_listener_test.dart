import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/auth/ui/bloc/auth_state.dart';
import 'package:tentura/features/auth/ui/widget/auth_recovery_listener.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/auth/domain/exception.dart';

void main() {
  group('authRecoveryListenerShouldListen', () {
    final base = AuthState(updatedAt: DateTime.utc(2026));

    test('reacts to first loading-to-error transition', () {
      final previous = base.copyWith(status: StateStatus.isLoading);
      final current = base.copyWith(
        status: StateHasError(const AuthSessionLostException()),
      );

      expect(authRecoveryListenerShouldListen(previous, current), isTrue);
    });

    test('ignores unchanged error status', () {
      final error = StateHasError(const AuthSessionLostException());
      final previous = base.copyWith(status: error);
      final current = base.copyWith(status: error);

      expect(authRecoveryListenerShouldListen(previous, current), isFalse);
    });

    test('reacts to authRecoveryNeeded changes', () {
      final previous = base;
      final current = base.copyWith(authRecoveryNeeded: true);

      expect(authRecoveryListenerShouldListen(previous, current), isTrue);
    });
  });
}
