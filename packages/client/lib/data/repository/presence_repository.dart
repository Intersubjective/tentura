import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';

import '../service/user_presence_service.dart';

@lazySingleton
class PresenceRepository {
  PresenceRepository(this._service);

  final UserPresenceService _service;

  Stream<Map<String, UserPresenceStatus>> get presenceChanges =>
      _service.presenceChanges;

  UserPresenceStatus? statusOf(String userId) => _service.snapshot[userId];

  void watch(String sourceKey, Set<String> userIds) =>
      _service.setWatchPeers(sourceKey, userIds);

  void unwatch(String sourceKey) => _service.removeWatch(sourceKey);
}
