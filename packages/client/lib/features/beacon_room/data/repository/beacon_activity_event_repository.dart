import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';

import '../gql/_g/beacon_activity_event_list.req.gql.dart';

@lazySingleton
class BeaconActivityEventRepository {
  BeaconActivityEventRepository(
    this._remote,
    InvalidationService invalidationService,
  ) {
    _sub = invalidationService.beaconRoomInvalidations.listen((beaconId) {
      if (!_changes.isClosed) {
        _changes.add(beaconId);
      }
    });
  }

  static const _label = 'BeaconActivityEvent';

  final RemoteApiService _remote;

  late final StreamSubscription<String> _sub;

  final _changes = StreamController<String>.broadcast();

  Stream<String> get changes => _changes.stream;

  Future<List<BeaconActivityEvent>> list({required String beaconId}) async {
    final r = await _remote
        .request(
          GBeaconActivityEventListReq((b) => b.vars.beaconId = beaconId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final rows = r.dataOrThrow(label: _label).BeaconActivityEventList;
    return [
      for (final e in rows)
        BeaconActivityEvent(
          id: e.id,
          beaconId: e.beaconId,
          visibility: e.visibility,
          type: e.type,
          actorId: e.actorId,
          targetUserId: e.targetUserId,
          sourceMessageId: e.sourceMessageId,
          diffJson: e.diffJson,
          createdAt: DateTime.parse(e.createdAt),
        ),
    ];
  }

  @disposeMethod
  Future<void> dispose() async {
    await _sub.cancel();
    await _changes.close();
  }
}
