import 'dart:async';

import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/domain/entity/beacon.dart';

import '../../data/my_field_repository.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

part 'my_field_state.dart';

class MyFieldCubit extends Cubit<MyFieldState> {
  MyFieldCubit(this._repository) : super(const MyFieldState()) {
    fetch();
  }

  final MyFieldRepository _repository;

  Future<void> fetch([String? contextName]) async {
    emit(state.setLoading());
    try {
      final beacons = await _repository.fetch(
        context: contextName ?? state.context,
      );
      emit(MyFieldState(
        context: contextName ?? state.context,
        beacons: beacons.toList(),
      ));
    } catch (e) {
      emit(state.setError(e));
    }
  }
}
