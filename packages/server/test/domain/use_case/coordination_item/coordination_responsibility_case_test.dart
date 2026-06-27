import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/entity/coordination_responsibility_counts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/coordination_responsibility_case.dart';
import 'package:tentura_server/env.dart';
import '../../../support/coordination_item_record_fixtures.dart';

class _RecordingItemsPort extends Fake
    implements CoordinationItemRepositoryPort {
  List<String>? batchBeaconIds;
  String? myItemsBeaconId;
  String? markSeenUserId;
  String? markSeenBeaconId;

  @override
  Future<List<CoordinationResponsibilityCounts>>
  responsibilityCountsByBeaconIds({
    required String viewerUserId,
    required List<String> beaconIds,
  }) async {
    batchBeaconIds = List<String>.from(beaconIds);
    return [
      for (final id in beaconIds)
        CoordinationResponsibilityCounts(
          beaconId: id,
          askOpen: id == 'b1' ? 2 : 0,
          promiseOpen: id == 'b2' ? 1 : 0,
        ),
    ];
  }

  @override
  Future<List<CoordinationItemWithCounts>> myResponsibilityItemsByBeacon({
    required String viewerUserId,
    required String beaconId,
  }) async {
    myItemsBeaconId = beaconId;
    if (beaconId == 'b1') {
      return [
        _item(id: 'ask-1', beaconId: beaconId, kind: coordinationItemKindAsk),
        _item(id: 'ask-2', beaconId: beaconId, kind: coordinationItemKindAsk),
      ];
    }
    if (beaconId == 'b2') {
      return [
        _item(
          id: 'promise-1',
          beaconId: beaconId,
          kind: coordinationItemKindPromise,
        ),
      ];
    }
    return const [];
  }

  @override
  Future<DateTime> markBeaconItemsSeen({
    required String userId,
    required String beaconId,
  }) async {
    markSeenUserId = userId;
    markSeenBeaconId = beaconId;
    return DateTime.utc(2026, 6, 1, 12);
  }

  CoordinationItemWithCounts _item({
    required String id,
    required String beaconId,
    required int kind,
  }) {
    final now = DateTime.utc(2026, 5);
    return CoordinationItemWithCounts(
      item: testCoordinationItem(
        id: id,
        beaconId: beaconId,
        kind: kind,
        title: id,
        creatorId: 'Uaaaaaaaaaaaa',
        createdAt: now,
        updatedAt: now,
      ),
      messageCount: 0,
      unreadCount: 0,
    );
  }
}

class _AllowRoom extends Fake implements BeaconRoomRepositoryPort {
  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => true;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => false;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async => null;
}

class _SelectiveRoom extends Fake implements BeaconRoomRepositoryPort {
  _SelectiveRoom({required this.allowedBeaconIds});

  final Set<String> allowedBeaconIds;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => allowedBeaconIds.contains(beaconId);

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => false;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async => null;
}

class _DenyRoom extends _SelectiveRoom {
  _DenyRoom() : super(allowedBeaconIds: const {});
}

void main() {
  late _RecordingItemsPort items;
  late CoordinationResponsibilityCase sut;

  const viewerUserId = 'Uaaaaaaaaaaaa';

  setUp(() {
    items = _RecordingItemsPort();
    sut = CoordinationResponsibilityCase(
      items,
      _AllowRoom(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationResponsibilityCaseTest'),
    );
  });

  test('batch dedupes beacon ids and caps at 80', () async {
    final ids = [for (var i = 0; i < 85; i++) 'beacon-$i'];
    final rows = await sut.batch(
      viewerUserId: viewerUserId,
      beaconIds: [...ids, ids.first],
    );

    expect(items.batchBeaconIds, hasLength(80));
    expect(rows, hasLength(80));
  });

  test('batch skips unauthorized beacon ids without throwing', () async {
    sut = CoordinationResponsibilityCase(
      items,
      _SelectiveRoom(allowedBeaconIds: const {'b1'}),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationResponsibilityCaseTest'),
    );

    final rows = await sut.batch(
      viewerUserId: viewerUserId,
      beaconIds: const ['b1', 'blocked'],
    );

    expect(items.batchBeaconIds, ['b1']);
    expect(rows.map((r) => r.beaconId), ['b1']);
  });

  test(
    'myItems returns rows matching per-kind open counts for fixture beacons',
    () async {
      final counts = await sut.batch(
        viewerUserId: viewerUserId,
        beaconIds: const ['b1', 'b2'],
      );
      final b1Counts = counts.singleWhere((r) => r.beaconId == 'b1');
      final b2Counts = counts.singleWhere((r) => r.beaconId == 'b2');

      final b1Items = await sut.myItems(
        viewerUserId: viewerUserId,
        beaconId: 'b1',
      );
      final b2Items = await sut.myItems(
        viewerUserId: viewerUserId,
        beaconId: 'b2',
      );

      expect(
        b1Items.where((e) => e.item.kind == coordinationItemKindAsk).length,
        b1Counts.askOpen,
      );
      expect(
        b2Items.where((e) => e.item.kind == coordinationItemKindPromise).length,
        b2Counts.promiseOpen,
      );
    },
  );

  test('markSeen delegates to port with viewer and beacon ids', () async {
    final seenAt = await sut.markSeen(
      viewerUserId: viewerUserId,
      beaconId: 'b1',
    );

    expect(items.markSeenUserId, viewerUserId);
    expect(items.markSeenBeaconId, 'b1');
    expect(seenAt, DateTime.utc(2026, 6, 1, 12));
  });

  test('myItems still rejects unauthorized beacon ids', () async {
    sut = CoordinationResponsibilityCase(
      items,
      _DenyRoom(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationResponsibilityCaseTest'),
    );

    expect(
      () => sut.myItems(viewerUserId: viewerUserId, beaconId: 'blocked'),
      throwsA(isA<BeaconCreateException>()),
    );
  });

  test('markSeen still rejects unauthorized beacon ids', () async {
    sut = CoordinationResponsibilityCase(
      items,
      _DenyRoom(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationResponsibilityCaseTest'),
    );

    expect(
      () => sut.markSeen(viewerUserId: viewerUserId, beaconId: 'blocked'),
      throwsA(isA<BeaconCreateException>()),
    );
  });
}
