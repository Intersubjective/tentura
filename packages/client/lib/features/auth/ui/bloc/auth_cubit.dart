//
// ignore_for_file: prefer_void_public_cubit_methods
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/message/common_messages.dart';

import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../domain/entity/account_entity.dart';
import '../../domain/entity/auth_recovery_outcome.dart';
import '../../domain/exception.dart';
import '../../domain/use_case/account_case.dart';
import '../../domain/use_case/auth_case.dart';
import 'auth_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'auth_state.dart';

const _bootstrapTimeout = Duration(seconds: 10);

/// Global Cubit
@singleton
class AuthCubit extends Cubit<AuthState> {
  @FactoryMethod(preResolve: true)
  static Future<AuthCubit> hydrated(
    Env env,
    AuthCase authCase,
    AccountCase accountCase,
    ProfileRepositoryPort profileRepository,
  ) async {
    final accounts = await accountCase.getAccountsAll();
    final cubit = AuthCubit._(
      env,
      authCase,
      accountCase,
      profileRepository,
      AuthState(
        accounts: accounts..sort(_compareAccounts),
        updatedAt: DateTime.timestamp(),
        isBootstrapping: true,
      ),
    );
    unawaited(cubit._bootstrap());
    return cubit;
  }

  AuthCubit._(
    this._env,
    this._authCase,
    this._accountCase,
    ProfileRepositoryPort profileRepository,
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

  var _authTransitionDepth = 0;

  String? _pendingSuppressedAccountId;

  String get inviteEmail => _env.inviteEmail;

  @disposeMethod
  Future<void> dispose() async {
    await _authChanges.cancel();
    await _profileChanges.cancel();
    return close();
  }

  Future<void> _bootstrap() async {
    try {
      final bootstrap = await _authCase
          .bootstrapWebSession()
          .timeout(_bootstrapTimeout);
      var next = state.copyWith(
        currentAccountId: bootstrap.currentAccountId,
        isBootstrapping: false,
        updatedAt: DateTime.timestamp(),
      );
      if (bootstrap.invalidSessionCookieRejected && next.isNotAuthenticated) {
        _authCase.reloadAfterRejectedSession(
          clearAcknowledged: bootstrap.sessionCookieClearAcknowledged,
        );
        emit(next);
        return;
      }
      if (next.isAuthenticated) {
        _authCase.noteAuthenticatedBoot();
        try {
          await _authCase
              .signIn(userId: next.currentAccountId)
              .timeout(_bootstrapTimeout);
        } on AuthSessionLostException {
          next = next.copyWith(
            authRecoveryNeeded: true,
            authSessionLossCount: 1,
            currentAccountId: '',
          );
        } catch (_) {
          next = next.copyWith(
            authRecoveryNeeded: true,
            authSessionLossCount: 1,
            currentAccountId: '',
          );
        }
      }
      emit(next);
    } on TimeoutException {
      emit(
        state.copyWith(
          isBootstrapping: false,
          authRecoveryNeeded: true,
          authSessionLossCount: 2,
          currentAccountId: '',
          updatedAt: DateTime.timestamp(),
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isBootstrapping: false,
          authRecoveryNeeded: true,
          authSessionLossCount: 1,
          updatedAt: DateTime.timestamp(),
        ),
      );
    }
  }

  void noteAuthSessionLoss(Object error) {
    if (error is! AuthSessionLostException) {
      return;
    }
    final count = state.authSessionLossCount + 1;
    emit(
      state.copyWith(
        authRecoveryNeeded: true,
        authSessionLossCount: count,
        status: const StateIsSuccess(),
      ),
    );
  }

  void dismissAuthRecoveryBanner() {
    emit(
      state.copyWith(
        authRecoveryNeeded: false,
        status: const StateIsSuccess(),
      ),
    );
  }

  Future<void> signInAgain() async {
    await _duringAuthTransition(() async {
      emit(state.copyWith(status: StateStatus.isLoading));
      try {
        final outcome = await _authCase.signInAgain();
        final nav = _applyRecoveryOutcome(outcome);
        if (nav.pageUnloading) {
          return;
        }
        emit(
          AuthState(
            accounts: state.accounts,
            updatedAt: DateTime.timestamp(),
            pendingRecoveryNavigation: nav.pending,
          ),
        );
      } catch (e) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    });
  }

  Future<void> resetLocalAuthState() async {
    await _duringAuthTransition(() async {
      emit(state.copyWith(status: StateStatus.isLoading));
      try {
        final outcome = await _authCase.resetLocalAuthState();
        final nav = _applyRecoveryOutcome(outcome);
        if (nav.pageUnloading) {
          return;
        }
        emit(
          AuthState(
            accounts: const [],
            updatedAt: DateTime.timestamp(),
            pendingRecoveryNavigation: nav.pending,
          ),
        );
      } catch (e) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    });
  }

  Future<bool> hasSeedOnlyLocalAccounts() => _authCase.hasSeedOnlyLocalAccounts();

  ({bool pageUnloading, AuthRecoveryNavigation? pending}) _applyRecoveryOutcome(
    AuthRecoveryOutcome outcome,
  ) {
    switch (outcome.navigation) {
      case AuthRecoveryNavigation.webInviteLanding:
        _authCase.applyRecoveryNavigation(outcome);
        return (pageUnloading: true, pending: null);
      case AuthRecoveryNavigation.nativeLogin:
      case AuthRecoveryNavigation.nativeBack:
        return (pageUnloading: false, pending: outcome.navigation);
      case AuthRecoveryNavigation.none:
        return (pageUnloading: false, pending: null);
    }
  }

  Future<T> _duringAuthTransition<T>(Future<T> Function() action) async {
    _authTransitionDepth++;
    try {
      return await action();
    } finally {
      _authTransitionDepth--;
      if (_authTransitionDepth == 0) {
        final pendingId = _pendingSuppressedAccountId;
        _pendingSuppressedAccountId = null;
        if (pendingId != null &&
            !isClosed &&
            pendingId != state.currentAccountId) {
          _emitAuthChanged(pendingId);
        }
      }
    }
  }

  void clearPendingRecoveryNavigation() {
    if (state.pendingRecoveryNavigation == null) {
      return;
    }
    emit(
      state.copyWith(
        pendingRecoveryNavigation: null,
        status: const StateIsSuccess(),
      ),
    );
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

  ///
  /// Web recovery: validate seed, sign in, upsert local account, stay current.
  ///
  Future<void> recoverAndSignIn(String seed) async {
    if (seed.trim().isEmpty) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _accountCase.recoverFromSeedAndSignIn(seed);
      final accounts = await _accountCase.getAccountsAll()
        ..sort(_compareAccounts);
      final currentAccountId = await _accountCase.getCurrentAccountId();
      emit(
        AuthState(
          accounts: accounts,
          currentAccountId: currentAccountId,
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
    required String displayName,
    required String invitationCode,
    String? handle,
  }) async {
    if (_env.needInviteCode && invitationCode.length < kIdLength) {
      return emit(
        state.copyWith(
          status: StateHasError(const InvitationCodeIsWrongException()),
        ),
      );
    }
    if (displayName.length < kTitleMinLength) {
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
          displayName: displayName,
          handle: handle,
        ),
        displayName: displayName,
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
      emit(
        state.copyWith(
          authRecoveryNeeded: false,
          authSessionLossCount: 0,
          status: const StateIsSuccess(),
        ),
      );
    } on AuthSessionLostException catch (e) {
      noteAuthSessionLoss(e);
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> signOut() async {
    await _duringAuthTransition(() async {
      emit(state.copyWith(status: StateStatus.isLoading));
      try {
        final outcome = await _authCase.signOut();
        final nav = _applyRecoveryOutcome(outcome);
        if (nav.pageUnloading) {
          return;
        }
        emit(
          AuthState(
            accounts: kIsWeb ? const [] : state.accounts,
            updatedAt: DateTime.timestamp(),
            pendingRecoveryNavigation: nav.pending,
          ),
        );
      } catch (e) {
        emit(state.copyWith(status: StateHasError(e)));
      }
      _authCase.logger.fine('Sign out');
    });
  }

  ///
  /// Remove account from local storage
  ///
  Future<void> removeAccount(String id) async {
    await _duringAuthTransition(() async {
      emit(state.copyWith(status: StateStatus.isLoading));
      try {
        await _accountCase.removeAccount(id);
        final outcome = await _authCase.signOut();
        final nav = _applyRecoveryOutcome(outcome);
        if (nav.pageUnloading) {
          return;
        }
        emit(
          AuthState(
            accounts: state.accounts..removeWhere((e) => e.id == id),
            updatedAt: DateTime.timestamp(),
            pendingRecoveryNavigation: nav.pending,
          ),
        );
      } catch (e) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    });
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
  void _onAuthChanged(String id) {
    if (_authTransitionDepth > 0) {
      _pendingSuppressedAccountId = id;
      return;
    }
    _emitAuthChanged(id);
  }

  void _emitAuthChanged(String id) {
    emit(
      AuthState(
        accounts: state.accounts,
        currentAccountId: id,
        authRecoveryNeeded: state.authRecoveryNeeded,
        authSessionLossCount: state.authSessionLossCount,
        updatedAt: DateTime.timestamp(),
      ),
    );
  }

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

        if (account.displayName == event.value.displayName &&
            account.image == event.value.image) {
          return;
        }

        try {
          await _accountCase.updateAccount(account);

          state.accounts[index] = account.copyWith(
            displayName: event.value.displayName,
            image: event.value.image,
          );
          emit(
            AuthState(
              accounts: state.accounts,
              currentAccountId: state.currentAccountId,
              authRecoveryNeeded: state.authRecoveryNeeded,
              authSessionLossCount: state.authSessionLossCount,
              updatedAt: DateTime.timestamp(),
            ),
          );
        } catch (e) {
          emit(state.copyWith(status: StateHasError(e)));
        }

      case RepositoryEventCreate<Profile>():
      case RepositoryEventInvalidate<Profile>():
    }
  }

  //
  //
  static int _compareAccounts(AccountEntity left, AccountEntity right) =>
      left.id.compareTo(right.id);
}
