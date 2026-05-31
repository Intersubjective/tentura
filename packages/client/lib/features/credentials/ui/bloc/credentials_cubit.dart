import 'dart:async';
import 'package:injectable/injectable.dart';

import '../../data/repository/credentials_repository.dart';
import 'credentials_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'credentials_state.dart';

@injectable
class CredentialsCubit extends Cubit<CredentialsState> {
  CredentialsCubit(this._repository)
    : super(CredentialsState(updatedAt: DateTime.timestamp())) {
    unawaited(fetch());
  }

  final CredentialsRepository _repository;

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final credentials = await _repository.fetchCredentials();
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
      await _repository.removeCredential(id);
      await fetch();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
