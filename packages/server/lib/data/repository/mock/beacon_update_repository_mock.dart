import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_update_entity.dart';
import 'package:tentura_server/domain/port/beacon_update_repository_port.dart';

@Injectable(
  as: BeaconUpdateRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class BeaconUpdateRepositoryMock implements BeaconUpdateRepositoryPort {
  const BeaconUpdateRepositoryMock();

  static final _byBeacon = <String, List<BeaconUpdateEntity>>{};

  static int _seq = 0;

  @override
  Future<BeaconUpdateEntity> createUpdate({
    required String beaconId,
    required String authorId,
    required String content,
  }) async {
    _seq++;
    final list = _byBeacon.putIfAbsent(beaconId, () => []);
    final n = list.isEmpty
        ? 1
        : (list.map((e) => e.number).reduce((a, b) => a > b ? a : b) + 1);
    final e = BeaconUpdateEntity(
      id: 'A$_seq',
      beaconId: beaconId,
      authorId: authorId,
      content: content,
      number: n,
      createdAt: DateTime.timestamp(),
    );
    list.add(e);
    return e;
  }

  @override
  Future<BeaconUpdateEntity> editUpdate({
    required String id,
    required String authorId,
    required String content,
  }) async {
    for (final list in _byBeacon.values) {
      final i = list.indexWhere((e) => e.id == id && e.authorId == authorId);
      if (i >= 0) {
        final old = list[i];
        final next = BeaconUpdateEntity(
          id: old.id,
          beaconId: old.beaconId,
          authorId: old.authorId,
          content: content,
          number: old.number,
          createdAt: old.createdAt,
        );
        list[i] = next;
        return next;
      }
    }
    throw StateError('Beacon update not found: $id');
  }

  @override
  Future<BeaconUpdateEntity?> getById(String id) {
    for (final list in _byBeacon.values) {
      for (final e in list) {
        if (e.id == id) return Future.value(e);
      }
    }
    return Future.value();
  }

  @override
  Future<List<BeaconUpdateEntity>> fetchByBeaconId(String beaconId) =>
      Future.value(List.unmodifiable(_byBeacon[beaconId] ?? const []));
}
