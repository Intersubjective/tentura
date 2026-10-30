import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

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

/// #498 — the Requests card preview of a photo-, file-, poll- or fact-only
/// message. `inboxRoomContextBatch` carries the latest message's kind
/// (`lastMessageKind`: image, file, poll, fact; null for text) beside its
/// text, and the GraphQL row type exposes it, so the client can render
/// "📷 Photo" instead of "—".
void main() {
  const userId = 'Uviewer';
  const photoBeacon = 'Bphoto';
  const textBeacon = 'Btext';

  late _LatestStubRoom room;
  late BeaconRoomCase sut;

  setUp(() {
    room = _LatestStubRoom(authoredBeaconIds: {photoBeacon, textBeacon});
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
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCaseLatestKindBatchTest'),
    );
  });

  test(
    'a photo-only latest message reaches the batch row with its kind',
    () async {
      room.latest = {
        photoBeacon: RoomLatestActivity(
          lastActivityAt: DateTime.utc(2026, 1, 2, 11),
          lastMessageAt: DateTime.utc(2026, 1, 2, 11),
          lastMessageAuthorId: 'Unina',
          lastMessageAuthorName: 'Nina',
          lastMessageKind: 'image',
        ),
        textBeacon: RoomLatestActivity(
          lastActivityAt: DateTime.utc(2026, 1, 2, 10),
          lastMessageAt: DateTime.utc(2026, 1, 2, 10),
          lastMessageBody: 'Parking sorted?',
          lastMessageAuthorId: 'Unina',
          lastMessageAuthorName: 'Nina',
        ),
      };

      final rows = await sut.inboxRoomContextBatch(
        userId: userId,
        beaconIds: const [photoBeacon, textBeacon],
      );
      final byId = {for (final r in rows) r['beaconId']: r};

      expect(byId[photoBeacon]!['isRoomMember'], isTrue);
      expect(byId[photoBeacon]!['lastMessageKind'], 'image');
      expect(byId[photoBeacon]!['lastMessageText'], isNull);
      expect(byId[photoBeacon]!['lastMessageAuthorId'], 'Unina');
      expect(
        byId[photoBeacon]!['lastMessageAt'],
        DateTime.utc(2026, 1, 2, 11).toIso8601String(),
      );
      // Guard: a text message keeps its text and has no kind.
      expect(byId[textBeacon]!['lastMessageText'], 'Parking sorted?');
      expect(byId[textBeacon]!['lastMessageKind'], isNull);
    },
  );

  test('InboxRoomContextRow exposes lastMessageKind as a nullable String', () {
    final field = gqlTypeInboxRoomContextRow.fields
        .where((f) => f.name == 'lastMessageKind')
        .toList();
    expect(field, hasLength(1));
    expect(field.single.type.name, 'String');
  });
}

class _LatestStubRoom extends Fake
    with RoomReadsFromPerRequestStubs
    implements BeaconRoomRepositoryPort {
  @override
  Future<Map<String, String>> postRootExcerpts(
    Iterable<String> beaconIds, {
    required String viewerUserId,
  }) async => {};

  _LatestStubRoom({required this.authoredBeaconIds});

  final Set<String> authoredBeaconIds;

  Map<String, RoomLatestActivity> latest = const {};

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
  }) async => {
    for (final id in beaconIds)
      if (latest[id] case final RoomLatestActivity a) id: a,
  };

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
