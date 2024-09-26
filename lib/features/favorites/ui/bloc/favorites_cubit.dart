import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/beacon/domain/entity/beacon.dart';

import '../../domain/use_case/favorites_case.dart';
import 'favorites_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'favorites_state.dart';

@lazySingleton
class FavoritesCubit extends Cubit<FavoritesState> {
  FavoritesCubit(
    this._favoritesCase, {
    required String userId,
  }) : super(FavoritesState(
          userId: userId,
          beacons: {},
        )) {
    _authChanges.resume();
    _favoritesChanges.resume();
  }

  final FavoritesCase _favoritesCase;

  late final _authChanges = _favoritesCase.currentAccountChanges.listen(
    (userId) {
      emit(FavoritesState(
        userId: userId,
        beacons: {},
      ));
      fetch();
    },
    cancelOnError: false,
  );

  late final _favoritesChanges = _favoritesCase.favoritesChanges.listen(
    (beacon) {
      beacon.isPinned
          ? state.beacons.add(beacon)
          : state.beacons.removeWhere((e) => e.id == beacon.id);
      emit(state.copyWith(status: FetchStatus.isSuccess));
    },
    cancelOnError: false,
  );

  Stream<Beacon> get favoritesChanges => _favoritesCase.favoritesChanges;

  @override
  @disposeMethod
  Future<void> close() async {
    await _authChanges.cancel();
    await _favoritesChanges.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    emit(state.setLoading());
    try {
      emit(FavoritesState(
        beacons: (await _favoritesCase.fetch()).toSet(),
        userId: state.userId,
      ));
    } catch (e) {
      emit(state.setError(e.toString()));
    }
  }

  Future<void> pin(Beacon beacon) async {
    emit(state.setLoading());
    try {
      await _favoritesCase.pin(beacon);
    } catch (e) {
      emit(state.setError(e.toString()));
    }
  }

  Future<void> unpin(Beacon beacon) async {
    try {
      await _favoritesCase.unpin(
        beacon: beacon,
        userId: state.userId,
      );
    } catch (e) {
      emit(state.setError(e.toString()));
    }
  }
}
