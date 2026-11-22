import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/routing_mute_port.dart';

@Injectable(
  as: RoutingMutePort,
  env: [Environment.test],
  order: 1,
)
class RoutingMuteRepositoryMock implements RoutingMutePort {
  @override
  Future<Map<String, Set<String>>> mutedSlugsFor({
    required List<String> subjectIds,
  }) => Future.value(const {});

  @override
  Future<Set<String>> mutedSlugsForUser(String userId) =>
      Future.value(const {});

  @override
  Future<void> setMute({
    required String userId,
    required String tagSlug,
    required bool muted,
  }) => Future.value();

  @override
  Future<Map<String, int>> muteCountsByTag() => Future.value(const {});
}
