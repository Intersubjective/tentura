import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';

import '../../data/repository/my_field_repository.dart';
import 'my_field_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_field_state.dart';

class MyFieldCubit extends Cubit<MyFieldState> {
  MyFieldCubit({
    String initialContext = '',
    MyFieldRepository? repository,
  }) : _repository = repository ?? GetIt.I<MyFieldRepository>(),
       super(const MyFieldState()) {
    unawaited(fetch(initialContext));
  }

  final MyFieldRepository _repository;

  ///
  ///
  Future<void> fetch([String? contextName]) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final beacons = (await _repository.fetch(
        context: contextName ?? state.context,
      )).toList();
      final tags = beacons.expand((beacon) => beacon.tags).toSet().toList()
        ..sort();
      final selectedTags = state.selectedTags.where(tags.contains).toList();
      emit(
        MyFieldState(
          tags: tags,
          beacons: beacons,
          selectedTags: selectedTags,
          context: contextName ?? state.context,
          visibleBeacons: _filterBeacons(beacons, selectedTags),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  void addTag(String tag) {
    if (!state.selectedTags.contains(tag)) {
      final selectedTags = [...state.selectedTags, tag]..sort();
      emit(
        state.copyWith(
          selectedTags: selectedTags,
          visibleBeacons: _filterBeacons(
            state.beacons,
            selectedTags,
          ),
        ),
      );
    }
  }

  ///
  ///
  void removeTag(String tag) {
    if (state.selectedTags.contains(tag)) {
      final selectedTags = state.selectedTags.where((e) => e != tag).toList();
      emit(
        state.copyWith(
          selectedTags: selectedTags,
          visibleBeacons: _filterBeacons(
            state.beacons,
            selectedTags,
          ),
        ),
      );
    }
  }

  ///
  ///
  void setSelectedTags(Set<String> tags) {
    final selectedTags = tags.toList()..sort();
    emit(
      state.copyWith(
        selectedTags: selectedTags,
        visibleBeacons: _filterBeacons(
          state.beacons,
          selectedTags,
        ),
      ),
    );
  }

  List<Beacon> _filterBeacons(
    List<Beacon> beacons,
    List<String> selectedTags,
  ) => selectedTags.isEmpty
      ? beacons
      : beacons.where((e) => e.tags.any(selectedTags.contains)).toList();
}
