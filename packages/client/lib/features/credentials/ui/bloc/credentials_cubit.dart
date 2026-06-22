import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/localizable.dart';
import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/use_case/credentials_case.dart';
import 'credentials_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'credentials_state.dart';

@injectable
class CredentialsCubit extends Cubit<CredentialsState> {
  CredentialsCubit(
    this._case,
    this._platformRepository,
    this._effects,
  ) : super(CredentialsState(updatedAt: DateTime.timestamp())) {
    unawaited(fetch());
  }

  final CredentialsCase _case;
  final PlatformRepositoryPort _platformRepository;
  final UiEffectPort _effects;

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  void _emitSnackMessage(LocalizableMessage message) {
    _effects.emit(ShowMessage(message));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final credentials = await _case.fetch();
      emit(
        state.copyWith(
          credentials: credentials,
          status: StateStatus.isSuccess,
          updatedAt: DateTime.timestamp(),
        ),
      );
    } catch (e) {
      _emitSnackError(e);
    }
  }

  Future<void> remove(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.remove(id);
      await fetch();
    } catch (e) {
      _emitSnackError(_case.mapRemoveError(e));
    }
  }

  /// Returns the generated seed when linking succeeds (show-once backup).
  Future<String?> linkRecoverySeed() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final seed = await _case.linkRecoverySeed();
      await fetch();
      _emitSnackMessage(const CredentialLinkedMessage('seed'));
      return seed;
    } catch (e) {
      _emitSnackError(_case.mapLinkError(e));
      return null;
    }
  }

  Future<void> linkGoogleNative() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.linkGoogleNative();
      await fetch();
      _emitSnackMessage(const CredentialLinkedMessage('google'));
    } catch (e) {
      _emitSnackError(_case.mapLinkError(e));
    }
  }

  Future<void> linkGoogleWeb() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final url = await _case.googleLinkStartUrl();
      await _platformRepository.launchUrl(url);
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      _emitSnackError(_case.mapLinkError(e));
    }
  }

  Future<void> startEmailLink(String email) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.startEmailLink(email.trim());
      _emitSnackMessage(const CredentialEmailLinkSentMessage());
    } catch (e) {
      _emitSnackError(_case.mapLinkError(e));
    }
  }

  void notifyLinkedFromRedirect(String method) {
    unawaited(fetch());
    _emitSnackMessage(CredentialLinkedMessage(method));
  }
}
