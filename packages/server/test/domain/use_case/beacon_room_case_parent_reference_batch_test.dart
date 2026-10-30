import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/entity/room_latest_activity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/per_request_room_reads.dart';

/// #487 — on the Requests list a child Request ("Child: borrow moving
/// straps") read as an unrelated sibling of its parent ("Need a hand moving
/// a couch"): nothing on the card said it was part of another Request. The
/// client has no parent id on its list fetch (`beacon.parent_beacon_id` is
/// not exposed), so `inboxRoomContextBatch` — already read for every card —
/// carries the guarded parent link (one batched `loadParentReferences` read
/// for the whole slice, which checks that
/// the viewer may read both the child and the parent) as `parentBeaconId`
/// and `parentTitle`. A parent the viewer cannot read, or a Request with no
/// parent, carries neither.
void main() {
  const userId = 'Uviewer';
  const parentBeacon = 'Bcouch';
  const childBeacon = 'Bstraps';
  const foreignChild = 'Bforeign';
  const hiddenParentChild = 'Bhidden';
  const parentTitle = 'Need a hand moving a couch';

  late _ParentStubRoom room;
  late FakeBeaconHierarchyRepository hierarchy;
  late BeaconRoomCase sut;

  setUp(() {
    room = _ParentStubRoom(
      authoredBeaconIds: {parentBeacon, childBeacon, hiddenParentChild},
    );
    hierarchy = FakeBeaconHierarchyRepository()
      ..parentReferences.addAll({
        childBeacon: const BeaconParentReference(
          state: BeaconParentReferenceState.available,
          beaconId: parentBeacon,
          title: parentTitle,
        ),
        foreignChild: const BeaconParentReference(
          state: BeaconParentReferenceState.available,
          beaconId: parentBeacon,
          title: parentTitle,
        ),
        hiddenParentChild: BeaconParentReference.unavailable,
      });
    sut = BeaconRoomCase(
      room,
      _StubItems(),
      _NoFactCards(),
      _FakeImageRepositoryPort(),
      _FakeTaskRepositoryPort(),
      _FakeRemoteStorage(),
      _FakePollingRepository(),
      _FakeUploadQuota(),
      FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCaseParentReferenceBatchTest'),
    );
  });

  test('a child Request row names its parent (id and title)', () async {
    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: const [parentBeacon, childBeacon],
    );
    final byId = {for (final r in rows) r['beaconId']: r};

    expect(byId[childBeacon]!['isRoomMember'], isTrue);
    expect(byId[childBeacon]!['parentBeaconId'], parentBeacon);
    expect(byId[childBeacon]!['parentTitle'], parentTitle);
    // Guard: the top-level parent itself has no parent.
    expect(byId[parentBeacon]!['parentBeaconId'], isNull);
    expect(byId[parentBeacon]!['parentTitle'], isNull);
  });

  test(
    'the parent link rides the row even when the viewer is not in the room',
    () async {
      // A helper whose offer is still pending is not a room member, yet the
      // Request is on their list and its parent is readable to them.
      final rows = await sut.inboxRoomContextBatch(
        userId: userId,
        beaconIds: const [foreignChild],
      );
      final row = rows.single;

      expect(row['isRoomMember'], isFalse);
      expect(row['postRootExcerpt'], 'Root Post text');
      expect(row['parentBeaconId'], parentBeacon);
      expect(row['parentTitle'], parentTitle);
    },
  );

  test('guard: a parent the viewer cannot read is not revealed', () async {
    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: const [hiddenParentChild],
    );
    final row = rows.single;

    expect(row['isRoomMember'], isTrue);
    expect(row['parentBeaconId'], isNull);
    expect(row['parentTitle'], isNull);
  });

  test(
    'the slice reads every parent link in ONE batched call, never per Request',
    () async {
      // #487 review (PR #610): a per-id loadParentReference inside the
      // slice loop was up to 4 queries per Request (320 round trips for an
      // 80-id slice).
      final rows = await sut.inboxRoomContextBatch(
        userId: userId,
        beaconIds: const [
          parentBeacon,
          childBeacon,
          foreignChild,
          hiddenParentChild,
        ],
      );

      expect(rows, hasLength(4));
      expect(hierarchy.parentReferenceCalls, isEmpty);
      expect(hierarchy.parentReferencesBatchCalls, hasLength(1));
      final call = hierarchy.parentReferencesBatchCalls.single;
      expect(call.viewerId, userId);
      expect(call.childBeaconIds, {
        parentBeacon,
        childBeacon,
        foreignChild,
        hiddenParentChild,
      });
    },
  );

  test('the batched parent read covers exactly the 80-id slice', () async {
    final ids = [for (var i = 0; i < 85; i++) 'Bmany$i'];
    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: ids,
    );

    expect(rows, hasLength(80));
    expect(hierarchy.parentReferenceCalls, isEmpty);
    expect(hierarchy.parentReferencesBatchCalls, hasLength(1));
    expect(
      hierarchy.parentReferencesBatchCalls.single.childBeaconIds,
      ids.take(80).toSet(),
    );
  });

  test('InboxRoomContextRow exposes parentBeaconId and parentTitle as '
      'nullable Strings', () {
    for (final name in const ['parentBeaconId', 'parentTitle']) {
      final field = gqlTypeInboxRoomContextRow.fields
          .where((f) => f.name == name)
          .toList();
      expect(field, hasLength(1), reason: name);
      expect(field.single.type.name, 'String', reason: name);
    }
  });
}

class _ParentStubRoom extends Fake
    with RoomReadsFromPerRequestStubs
    implements BeaconRoomRepositoryPort {
  @override
  Future<Map<String, String>> postRootExcerpts(
    Iterable<String> beaconIds, {
    required String viewerUserId,
  }) async => {
    for (final id in beaconIds)
      if (id == 'Bforeign') id: 'Root Post text',
  };

  _ParentStubRoom({required this.authoredBeaconIds});

  final Set<String> authoredBeaconIds;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => authoredBeaconIds.contains(beaconId);

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

  @override
  Future<BeaconRoomStateRecord?> getBeaconRoomState(String beaconId) async =>
      null;

  @override
  Future<Map<String, RoomLatestActivity>> latestRoomActivities(
    Iterable<String> beaconIds, {
    required String viewerUserId,
  }) async => const {};

  @override
  Future<DateTime?> getMainRoomLastSeen({
    required String beaconId,
    required String userId,
  }) async => null;

  @override
  Future<int> countRoomMessagesAfter({
    required String beaconId,
    DateTime? after,
    String? excludeAuthorId,
  }) async => 0;
}

class _NoFactCards extends Fake implements BeaconFactCardRepositoryPort {
  @override
  Future<Map<String, String>> publicFactSnippetsByBeaconIds(
    List<String> beaconIds,
  ) async => const {};
}

class _StubItems extends Fake
    with OpenBlockersFromListByBeacon
    implements CoordinationItemRepositoryPort {
  @override
  Future<List<CoordinationItemWithCounts>> listByBeacon(
    String beaconId, {
    required String viewerUserId,
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool rootOnly = false,
  }) async => const [];
}

class _FakeImageRepositoryPort extends Fake implements ImageRepositoryPort {}

class _FakeTaskRepositoryPort extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePollingRepository extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}
