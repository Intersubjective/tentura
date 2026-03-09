//
// ignore_for_file: prefer_void_public_cubit_methods
import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/message/common_messages.dart';

import 'package:tentura/features/profile/data/repository/profile_repository.dart';

import '../../domain/exception.dart';
import '../../domain/entity/account_entity.dart';
import '../../domain/use_case/account_case.dart';
import '../../domain/use_case/auth_case.dart';
import 'auth_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'auth_state.dart';

/// Global Cubit
@singleton
class AuthCubit extends Cubit<AuthState> {
  @FactoryMethod(preResolve: true)
  static Future<AuthCubit> hydrated(
    Env env,
    AuthCase authCase,
    AccountCase accountCase,
    ProfileRepository profileRepository,
  ) async {
    final accounts = await accountCase.getAccountsAll();
    var state = AuthState(
      accounts: accounts..sort(_compareAccounts),
      currentAccountId: await authCase.getCurrentAccountId(),
      updatedAt: DateTime.timestamp(),
    );
    if (state.isAuthenticated) {
      try {
        await authCase.signIn(
          userId: state.currentAccountId,
        );
      } catch (e) {
        state = state.copyWith(
          currentAccountId: '',
        );
      }
    }
    return AuthCubit(
      env,
      authCase,
      accountCase,
      profileRepository,
      state,
    );
  }

  AuthCubit(
    this._env,
    this._authCase,
    this._accountCase,
    ProfileRepository profileRepository,
    AuthState state,
  ) : super(state) {
    _authChanges = _authCase.currentAccountChanges().listen(
      _onAuthChanged,
      cancelOnError: false,
    );
    _profileChanges = profileRepository.changes.listen(
      _onProfileChanged,
      cancelOnError: false,
    );
  }

  final Env _env;

  final AuthCase _authCase;

  final AccountCase _accountCase;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<RepositoryEvent<Profile>> _profileChanges;

  String get inviteEmail => _env.inviteEmail;

  @disposeMethod
  Future<void> dispose() async {
    await _authChanges.cancel();
    await _profileChanges.cancel();
    return close();
  }

  //
  //
  Future<String> getInvitationCodeFromClipboard({
    bool supressError = false,
  }) async {
    try {
      final code = await _accountCase.getCodeFromClipboard(prefix: 'I');
      if (code.isEmpty) {
        emit(
          state.copyWith(
            status: StateIsMessaging(const NoValidCodeMessage()),
          ),
        );
      } else {
        return code;
      }
    } catch (e) {
      if (!supressError) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
    return '';
  }

  //
  //
  Future<String> getSeedByAccountId(String accountId) =>
      _accountCase.getSeedByAccountId(accountId);

  //
  //
  Future<String> getCodeFromClipboard() => _accountCase.getCodeFromClipboard();

  //
  //
  Future<void> openInviteEmailUrl() => _accountCase.openInviteEmailUrl();

  //
  //
  Future<void> addAccount(String? seed) async {
    if (seed == null || seed.isEmpty) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final account = await _accountCase.addAccount(seed);
      await _accountCase.updateAccount(account);
      emit(
        AuthState(
          accounts: state.accounts
            ..add(account)
            ..sort(_compareAccounts),
          updatedAt: DateTime.timestamp(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> signUp({
    required String title,
    required String invitationCode,
  }) async {
    if (_env.needInviteCode && invitationCode.length < kIdLength) {
      return emit(
        state.copyWith(
          status: StateHasError(const InvitationCodeIsWrongException()),
        ),
      );
    }
    if (title.length < kTitleMinLength) {
      return emit(
        state.copyWith(
          status: StateHasError(const TitleTooShortException()),
        ),
      );
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final newProfile = AccountEntity(
        id: await _authCase.signUp(
          invitationCode: invitationCode,
          title: title,
        ),
        title: title,
      );
      emit(
        AuthState(
          accounts: state.accounts
            ..add(newProfile)
            ..sort(_compareAccounts),
          currentAccountId: newProfile.id,
          updatedAt: DateTime.timestamp(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> signIn(String id) async {
    if (state.currentAccountId == id) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _authCase.signIn(userId: id);
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> signOut() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _authCase.signOut();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
    _authCase.logger.fine('Sign out');
  }

  ///
  /// Remove account from local storage
  ///
  Future<void> removeAccount(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _accountCase.removeAccount(id);
      await _authCase.signOut();
      emit(
        AuthState(
          accounts: state.accounts..removeWhere((e) => e.id == id),
          updatedAt: DateTime.timestamp(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> getSeedFromClipboard() async {
    try {
      await addAccount(await _accountCase.getSeedFromClipboard());
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  void _onAuthChanged(String id) => emit(
    AuthState(
      accounts: state.accounts,
      currentAccountId: id,
      updatedAt: DateTime.timestamp(),
    ),
  );

  //
  //
  Future<void> _onProfileChanged(RepositoryEvent<Profile> event) async {
    switch (event) {
      case RepositoryEventDelete<Profile>():
        await removeAccount(event.value.id);

      case RepositoryEventFetch<Profile>():
      case RepositoryEventUpdate<Profile>():
        final index = state.accounts.indexWhere((e) => e.id == event.value.id);

        if (index < 0) {
          return;
        }

        final account = state.accounts[index];

        if (account.title == event.value.title &&
            account.image == event.value.image) {
          return;
        }

        try {
          await _accountCase.updateAccount(account);

          state.accounts[index] = account.copyWith(
            title: event.value.title,
            image: event.value.image,
          );
          emit(
            AuthState(
              accounts: state.accounts,
              currentAccountId: state.currentAccountId,
              updatedAt: DateTime.timestamp(),
            ),
          );
        } catch (e) {
          emit(state.copyWith(status: StateHasError(e)));
        }

      case RepositoryEventCreate<Profile>():
    }
  }

  //
  //
  static int _compareAccounts(AccountEntity left, AccountEntity right) =>
      left.id.compareTo(right.id);
}
