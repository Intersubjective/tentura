import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/port/email_discoverability_repository_port.dart';

/// Null until the signed-in account's setting and dismissal are loaded.
typedef EmailDiscoverabilityState = ({
  bool enabled,
  bool explainerDismissed,
  bool saving,
});

/// Shares the confirmed setting between Home and Account and serializes writes.
@lazySingleton
class EmailDiscoverabilityCubit extends Cubit<EmailDiscoverabilityState?> {
  EmailDiscoverabilityCubit(this._repository, this._auth, this._effects)
    : super(null) {
    _accountChanges = _auth.stream.listen((state) {
      _bindAccount(state.currentAccountId);
    });
    _bindAccount(_auth.state.currentAccountId);
  }

  final EmailDiscoverabilityRepositoryPort _repository;
  final AuthCubit _auth;
  final UiEffectPort _effects;
  late final StreamSubscription<AuthState> _accountChanges;
  var _accountId = '';
  var _accountRevision = 0;

  void _bindAccount(String accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    final revision = ++_accountRevision;
    emit(null);
    if (accountId.isNotEmpty) unawaited(_load(accountId, revision));
  }

  bool _isCurrent(int revision) =>
      !isClosed &&
      revision == _accountRevision &&
      _accountId == _auth.state.currentAccountId;

  Future<void> _load(String accountId, int revision) async {
    try {
      final (enabled, dismissed) = await (
        _repository.fetchEnabled(),
        _repository.isExplainerDismissed(accountId),
      ).wait;
      if (_isCurrent(revision)) {
        emit((enabled: enabled, explainerDismissed: dismissed, saving: false));
      }
    } on Object catch (error) {
      if (_isCurrent(revision)) _effects.emit(ShowError(error));
    }
  }

  void setEnabled(bool enabled) => unawaited(
    _save(
      (current, _) async => (
        enabled: await _repository.setEnabled(enabled: enabled),
        explainerDismissed: current.explainerDismissed,
        saving: false,
      ),
    ),
  );

  void dismissExplainer() => unawaited(
    _save((current, accountId) async {
      await _repository.dismissExplainer(accountId);
      return (
        enabled: current.enabled,
        explainerDismissed: true,
        saving: false,
      );
    }),
  );

  Future<void> _save(
    Future<EmailDiscoverabilityState> Function(
      EmailDiscoverabilityState current,
      String accountId,
    )
    write,
  ) async {
    final current = state;
    final revision = _accountRevision;
    if (current == null || current.saving || !_isCurrent(revision)) return;
    emit((
      enabled: current.enabled,
      explainerDismissed: current.explainerDismissed,
      saving: true,
    ));
    try {
      final saved = await write(current, _accountId);
      if (_isCurrent(revision)) emit(saved);
    } on Object catch (error) {
      if (!_isCurrent(revision)) return;
      emit(current);
      _effects.emit(ShowError(error));
    }
  }

  @override
  @disposeMethod
  Future<void> close() async {
    await _accountChanges.cancel();
    await super.close();
  }
}
