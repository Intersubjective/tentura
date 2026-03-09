import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/account_entity.dart';

part 'auth_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class AuthState extends StateBase with _$AuthState {
  const factory AuthState({
    required DateTime updatedAt,
    @Default('') String currentAccountId,
    @Default([]) List<AccountEntity> accounts,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _AuthState;

  const AuthState._();

  bool get isAuthenticated => currentAccountId.isNotEmpty;

  bool get isNotAuthenticated => currentAccountId.isEmpty;

  AccountEntity get currentAccount => currentAccountId.isEmpty
      ? const AccountEntity(id: '')
      : accounts.singleWhere((e) => e.id == currentAccountId);

  bool checkIfIsMe(String id) => id == currentAccountId;
}
