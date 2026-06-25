import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/presence_repository.dart';

@singleton
class PresenceCubit extends Cubit<Map<String, UserPresenceStatus>> {
  PresenceCubit(PresenceRepository repository) : super(const {}) {
    _subscription = repository.presenceChanges.listen(emit);
  }

  late final StreamSubscription<Map<String, UserPresenceStatus>> _subscription;

  bool isOnline(String userId) =>
      state[userId] == UserPresenceStatus.online;

  @override
  @disposeMethod
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
