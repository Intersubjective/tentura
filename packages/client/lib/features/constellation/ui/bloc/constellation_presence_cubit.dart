import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/presence_repository.dart';

/// Who of the field's people is online now (state: their person ids).
///
/// Owns the field's presence watch: `watchIds` is the set of people the
/// field asks presence for (see `constellationPresenceWatchIds`). A new set
/// replaces the watch only when it differs from the last one, so a field
/// emitting on every drag or selection sends nothing. The state changes only
/// when a watched person comes online or goes away; presence of people the
/// field does not show never reaches it.
class ConstellationPresenceCubit extends Cubit<Set<String>> {
  ConstellationPresenceCubit({
    required Stream<Set<String>> watchIds,
    Set<String> initialWatchIds = const {},
    PresenceRepository? repository,
  }) : _repository = repository ?? GetIt.I<PresenceRepository>(),
       super(const <String>{}) {
    _presenceSub = _repository.presenceChanges.listen((_) => _sync());
    _watch(initialWatchIds);
    _watchIdsSub = watchIds.listen(_watch);
  }

  /// The presence watch source of the field.
  static const sourceKey = 'constellation';

  final PresenceRepository _repository;

  late final StreamSubscription<Map<String, UserPresenceStatus>> _presenceSub;
  late final StreamSubscription<Set<String>> _watchIdsSub;

  Set<String> _watched = const {};

  /// The ids the field watches now.
  Set<String> get watchedIds => _watched;

  bool isOnline(String personId) => state.contains(personId);

  void _watch(Set<String> ids) {
    if (isClosed || setEquals(ids, _watched)) {
      return;
    }
    final hadWatch = _watched.isNotEmpty;
    _watched = Set.unmodifiable(ids);
    if (_watched.isEmpty) {
      if (hadWatch) {
        _repository.unwatch(sourceKey);
      }
    } else {
      _repository.watch(sourceKey, _watched);
    }
    _sync();
  }

  void _sync() {
    if (isClosed) {
      return;
    }
    final online = <String>{
      for (final id in _watched)
        if (_repository.statusOf(id) == UserPresenceStatus.online) id,
    };
    if (!setEquals(online, state)) {
      emit(Set.unmodifiable(online));
    }
  }

  @override
  Future<void> close() {
    // Not awaited: a cancel with no teardown work completes in the root
    // zone, and awaiting it never resumes under a widget-test fake clock.
    unawaited(_watchIdsSub.cancel());
    unawaited(_presenceSub.cancel());
    if (_watched.isNotEmpty) {
      _repository.unwatch(sourceKey);
      _watched = const {};
    }
    return super.close();
  }
}
