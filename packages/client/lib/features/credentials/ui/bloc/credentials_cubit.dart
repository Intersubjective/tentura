import 'dart:async';
import 'package:injectable/injectable.dart';

import '../../domain/use_case/credentials_case.dart';
import 'credentials_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'credentials_state.dart';

@injectable
class CredentialsCubit extends Cubit<CredentialsState> {
  CredentialsCubit(this._case)
    : super(CredentialsState(updatedAt: DateTime.timestamp())) {
    unawaited(fetch());
  }

  final CredentialsCase _case;

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
}
