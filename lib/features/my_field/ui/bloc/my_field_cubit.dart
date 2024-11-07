import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/my_field_repository.dart';
import 'my_field_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_field_state.dart';

class MyFieldCubit extends Cubit<MyFieldState> {
  MyFieldCubit({
    String initialContext = '',
    MyFieldRepository? repository,
  })  : _repository = repository ?? GetIt.I<MyFieldRepository>(),
        super(const MyFieldState()) {
    fetch(initialContext);
  }

  final MyFieldRepository _repository;

  Future<void> fetch(String contextName) async {
    emit(state.setLoading());
    try {
      final beacons = await _repository.fetch(context: contextName);
      emit(MyFieldState(
        context: contextName,
        beacons: beacons.toList(),
      ));
    } catch (e) {
      emit(state.setError(e));
    }
  }
}
