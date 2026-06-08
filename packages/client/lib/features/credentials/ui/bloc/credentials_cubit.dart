import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';

import '../../domain/use_case/credentials_case.dart';
import 'credentials_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'credentials_state.dart';

@injectable
class CredentialsCubit extends Cubit<CredentialsState> {
  CredentialsCubit(
    this._case,
    this._platformRepository,
  ) : super(CredentialsState(updatedAt: DateTime.timestamp())) {
    unawaited(fetch());
  }

  final CredentialsCase _case;
  final PlatformRepositoryPort _platformRepository;

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
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> remove(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.remove(id);
      await fetch();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(_case.mapRemoveError(e))));
    }
  }

  /// Returns the generated seed when linking succeeds (show-once backup).
  Future<String?> linkRecoverySeed() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final seed = await _case.linkRecoverySeed();
      await fetch();
      emit(
        state.copyWith(
          status: StateIsMessaging(const CredentialLinkedMessage('seed')),
        ),
      );
      return seed;
    } catch (e) {
      emit(state.copyWith(status: StateHasError(_case.mapLinkError(e))));
      return null;
    }
  }

  Future<void> linkGoogleNative() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.linkGoogleNative();
      await fetch();
      emit(
        state.copyWith(
          status: StateIsMessaging(const CredentialLinkedMessage('google')),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(_case.mapLinkError(e))));
    }
  }

  Future<void> linkGoogleWeb() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final url = await _case.googleLinkStartUrl();
      await _platformRepository.launchUrl(url);
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(_case.mapLinkError(e))));
    }
  }

  Future<void> startEmailLink(String email) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.startEmailLink(email.trim());
      emit(
        state.copyWith(
          status: StateIsMessaging(const CredentialEmailLinkSentMessage()),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(_case.mapLinkError(e))));
    }
  }

  void notifyLinkedFromRedirect(String method) {
    unawaited(fetch());
    emit(
      state.copyWith(
        status: StateIsMessaging(CredentialLinkedMessage(method)),
      ),
    );
  }
}
