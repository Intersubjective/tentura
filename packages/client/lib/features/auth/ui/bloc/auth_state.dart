import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/account_entity.dart';
import '../../domain/entity/auth_recovery_outcome.dart';

part 'auth_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class AuthState extends StateBase with _$AuthState {
  const factory AuthState({
    required DateTime updatedAt,
    @Default('') String currentAccountId,
    @Default([]) List<AccountEntity> accounts,
    @Default(StateIsSuccess()) StateStatus status,
    @Default(false) bool isBootstrapping,
    @Default(false) bool authRecoveryNeeded,
    @Default(0) int authSessionLossCount,
    AuthRecoveryNavigation? pendingRecoveryNavigation,
  }) = _AuthState;

  const AuthState._();

  bool get isAuthenticated => currentAccountId.isNotEmpty;

  bool get isNotAuthenticated => currentAccountId.isEmpty;

  /// Session cookie probe / sign-in still running — router must not bounce to landing.
  bool get deferAuthRedirects => isBootstrapping;

  AccountEntity get currentAccount {
    if (currentAccountId.isEmpty) {
      return const AccountEntity(id: '');
    }
    for (final e in accounts) {
      if (e.id == currentAccountId) {
        return e;
      }
    }
    return const AccountEntity(id: '');
  }

  bool checkIfIsMe(String id) => id == currentAccountId;
}
