export 'package:flutter/foundation.dart';
export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:freezed_annotation/freezed_annotation.dart';

abstract class StateBase {
  const StateBase({
    this.status = const StateIsSuccess(),
  });

  final StateStatus status;

  bool get isSuccess => status is StateIsSuccess;

  bool get isLoading => status is StateIsLoading;
}

sealed class StateStatus {
  static const isSuccess = StateIsSuccess();

  static const isLoading = StateIsLoading();

  const StateStatus();
}

class StateIsSuccess extends StateStatus {
  const StateIsSuccess();
}

class StateIsLoading extends StateStatus {
  const StateIsLoading();
}
