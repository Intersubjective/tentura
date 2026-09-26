import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
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

/// tentura-617.15 (issue #181 plan §8.6): `inboxRoomContextBatch` reads the
/// public fact snippets of all its beacons with one
/// `publicFactSnippetsByBeaconIds` call before the per-beacon loop, and maps
/// them back by beacon id. The per-beacon `latestPublicFactSnippet` is gone.
///
/// Contract under test:
///
/// ```dart
/// Future<Map<String, String>> publicFactSnippetsByBeaconIds(
///   List<String> beaconIds,
/// );
/// ```
void main() {
  const userId = 'Uviewer';
  const authoredBeaconId = 'B0';

  late _InboxStubRoom room;
  late _CountingFactCards factCards;
  late BeaconRoomCase sut;

  setUp(() {
    room = _InboxStubRoom(authoredBeaconIds: {authoredBeaconId});
    factCards = _CountingFactCards();
    sut = BeaconRoomCase(
      room,
      _StubItems(),
      factCards,
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
      logger: Logger('BeaconRoomCaseInboxFactSnippetBatchTest'),
    );
  });

  tearDown(() {
    expect(
      factCards.otherCalls,
      isEmpty,
      reason: 'no per-beacon snippet reads (latestPublicFactSnippet)',
    );
  });

  test('calls publicFactSnippetsByBeaconIds once for N beacons', () async {
    final ids = List.generate(25, (i) => 'B$i');

    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: ids,
    );

    expect(rows, hasLength(25));
    expect(factCards.calls, 1);
    expect(factCards.requested.single.toSet(), ids.toSet());
  });

  test('batch call receives the 80-id cap, deduplicated', () async {
    final ids = [
      ...List.generate(90, (i) => 'B$i'),
      'B1',
      'B2',
    ];

    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: ids,
    );

    expect(rows, hasLength(80));
    expect(factCards.calls, 1);
    final requested = factCards.requested.single;
    expect(requested, hasLength(80));
    expect(requested.toSet(), rows.map((r) => r['beaconId']).toSet());
  });

  test('maps snippets back by beaconId for members and non-members', () async {
    factCards.snippets = {
      authoredBeaconId: 'member snippet',
      'B2': 'public snippet',
    };

    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: [authoredBeaconId, 'B1', 'B2'],
    );
    final byId = {for (final r in rows) r['beaconId']: r};

    expect(byId[authoredBeaconId]!['isRoomMember'], isTrue);
    expect(byId[authoredBeaconId]!['publicFactSnippet'], 'member snippet');
    expect(byId['B1']!['isRoomMember'], isFalse);
    expect(byId['B1']!['publicFactSnippet'], isNull);
    expect(byId['B2']!['isRoomMember'], isFalse);
    expect(byId['B2']!['publicFactSnippet'], 'public snippet');
    expect(factCards.calls, 1);
  });

  test('empty beaconIds makes no batch call', () async {
    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: const [],
    );

    expect(rows, isEmpty);
    expect(factCards.calls, 0);
  });
}

/// Counts batch calls. Any other port call (e.g. the old per-beacon
/// `latestPublicFactSnippet`) is recorded in [otherCalls] and throws, so a
/// use case that still reads snippets per beacon fails even if it swallows
/// the error.
class _CountingFactCards extends Fake implements BeaconFactCardRepositoryPort {
  int calls = 0;
  final requested = <List<String>>[];
  final otherCalls = <Symbol>[];
  Map<String, String> snippets = const {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    otherCalls.add(invocation.memberName);
    throw UnsupportedError(
      'inboxRoomContextBatch must only call publicFactSnippetsByBeaconIds; '
      'got ${invocation.memberName}',
    );
  }

  @override
  Future<Map<String, String>> publicFactSnippetsByBeaconIds(
    List<String> beaconIds,
  ) async {
    calls++;
    requested.add(List.of(beaconIds));
    return {
      for (final id in beaconIds)
        if (snippets[id] case final String s) id: s,
    };
  }
}

class _InboxStubRoom extends Fake implements BeaconRoomRepositoryPort {
  _InboxStubRoom({required this.authoredBeaconIds});

  final Set<String> authoredBeaconIds;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      authoredBeaconIds.contains(beaconId);

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async =>
      false;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async =>
      null;

  @override
  Future<BeaconRoomStateRecord?> getBeaconRoomState(String beaconId) async =>
      null;

  @override
  Future<DateTime?> getMainRoomLastSeen({
    required String beaconId,
    required String userId,
  }) async =>
      null;

  @override
  Future<int> countRoomMessagesAfter({
    required String beaconId,
    DateTime? after,
    String? excludeAuthorId,
  }) async =>
      0;
}

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
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
  }) async =>
      const [];
}

class _FakeImageRepositoryPort extends Fake implements ImageRepositoryPort {}

class _FakeTaskRepositoryPort extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePollingRepository extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}
