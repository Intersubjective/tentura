import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../support/coordination_item_record_fixtures.dart';
import '../support/fake_beacon_hierarchy_repository.dart';
import '../support/fake_user_block_repository.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

const _beaconId = 'Bgeneralonly01';
const _userId = 'Ugeneralonly01';
const _messageId = 'Rgeneralonly01';
const _threadItemId = 'CIaskgeneral01';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? itemById;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => itemById;
}

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  BeaconRoomMessageRecord? messageById;
  String? insertedBody;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      true;

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
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async =>
      0;

  @override
  Future<BeaconRoomMessageRecord?> getRoomMessageById(String id) async =>
      messageById;

  @override
  Future<BeaconRoomMessageRecord> insertRoomMessage({
    required String beaconId,
    required String authorId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    String? linkedParticipantId,
    String? linkedPollingId,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,
    List<String> mentions = const [],
    List<Map<String, Object?>> mentionSpans = const [],
  }) async {
    insertedBody = body;
    return BeaconRoomMessageRecord(
      id: _messageId,
      beaconId: beaconId,
      authorId: authorId,
      body: body,
      threadItemId: threadItemId,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  }) async {}

  @override
  Future<void> updateMessage({
    required String messageId,
    required String newBody,
    required List<String> mentions,
    required List<Map<String, Object?>> mentionSpans,
  }) async {}

  @override
  Future<void> deleteRoomMessage({required String messageId}) async {}
}

BeaconRoomCase _productionCase({
  required BeaconRoomRepositoryPort room,
  required CoordinationItemRepositoryPort items,
  required FakeBeaconHierarchyRepository hierarchy,
}) =>
    BeaconRoomCase(
      room,
      items,
      FakeBeaconFactCardRepository(),
      FakeImageRepositoryPort(),
      FakeTaskRepositoryPort(),
      FakeRemoteStorage(),
      FakePollingRepository(),
      FakeUploadQuota(),
      FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      env: Env(environment: Environment.test),
      logger: Logger('GeneralOnlyPublicContractTest'),
    );

void main() {
  group('production General-only contract', () {
    late _StubRoom room;
    late _StubItems items;
    late FakeBeaconHierarchyRepository hierarchy;
    late BeaconRoomCase sut;

    setUp(() {
      room = _StubRoom();
      items = _StubItems();
      hierarchy = FakeBeaconHierarchyRepository();
      sut = _productionCase(room: room, items: items, hierarchy: hierarchy);
      items.itemById = testCoordinationItem(
        id: _threadItemId,
        beaconId: _beaconId,
        kind: coordinationItemKindAsk,
        creatorId: _userId,
      );
    });

    test('createMessage rejects non-General thread scope', () async {
      await expectLater(
        sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: 'hello',
          threadItemId: _threadItemId,
        ),
        throwsA(isA<DiscussionScopeDisabledException>()),
      );
    });

    test('listMessages rejects non-General thread scope', () async {
      await expectLater(
        sut.listMessages(
          beaconId: _beaconId,
          userId: _userId,
          threadItemId: _threadItemId,
        ),
        throwsA(isA<DiscussionScopeDisabledException>()),
      );
    });

    test('markThreadSeen rejects non-General thread scope', () async {
      await expectLater(
        sut.markThreadSeen(
          beaconId: _beaconId,
          userId: _userId,
          threadId: _threadItemId,
        ),
        throwsA(isA<DiscussionScopeDisabledException>()),
      );
    });
  });

  group('lifecycle write guard', () {
    late _StubRoom room;
    late _StubItems items;
    late FakeBeaconHierarchyRepository hierarchy;
    late BeaconRoomCase sut;

    setUp(() {
      room = _StubRoom()
        ..messageById = BeaconRoomMessageRecord(
          id: _messageId,
          beaconId: _beaconId,
          authorId: _userId,
          body: 'original',
          createdAt: DateTime.utc(2026),
        );
      items = _StubItems();
      hierarchy = FakeBeaconHierarchyRepository()..statusOverride = BeaconStatus.closed;
      sut = _productionCase(room: room, items: items, hierarchy: hierarchy);
    });

    test('rejects ordinary user message create on closed request', () async {
      await expectLater(
        sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: 'blocked',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('rejects edit/delete/reaction/attachment on closed request', () async {
      await expectLater(
        sut.editMessage(
          beaconId: _beaconId,
          messageId: _messageId,
          userId: _userId,
          newBody: 'edited',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      await expectLater(
        sut.deleteMessage(
          beaconId: _beaconId,
          messageId: _messageId,
          userId: _userId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      await expectLater(
        sut.reactionToggle(
          beaconId: _beaconId,
          messageId: _messageId,
          userId: _userId,
          emoji: '👍',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('internal system notice path is not blocked by lifecycle guard helper',
        () async {
      hierarchy.statusOverride = BeaconStatus.closed;
      await expectLater(
        _rejectOrdinaryUserWritesProbe(hierarchy, _beaconId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(
        DiscussionProductPolicy.isSupportedCoordinationKind(
          DiscussionProductPolicy.kindPlan,
        ),
        isTrue,
      );
    });
  });

  group('retired public GraphQL mutations', () {
    const retired = {
      'markBlocker',
      'resolveBlocker',
      'cancelBlocker',
      'markAsk',
      'createPromise',
      'createDraftPromise',
      'publishPromise',
      'updateDraftPromise',
      'deleteDraftPromise',
      'acceptPromise',
      'resolvePromise',
      'cancelPromise',
      'redirectPromise',
      'createDraftAsk',
      'publishAsk',
      'updateDraftAsk',
      'deleteDraftAsk',
      'createDraftBlocker',
      'publishBlocker',
      'updateDraftBlocker',
      'deleteDraftBlocker',
      'acceptAsk',
      'resolveAsk',
      'cancelAsk',
      'redirectAsk',
    };

    test('MutationCoordinationItem.all exposes only retained plan surface', () {
      const names = {
        'updateCoordinationPlan',
        'addPlanStep',
        'resolvePlanStep',
        'updateCoordinationItem',
        'remindCoordinationItem',
        'markBeaconItemsSeen',
      };
      expect(names.intersection(retired), isEmpty);
      expect(names, {
        'updateCoordinationPlan',
        'addPlanStep',
        'resolvePlanStep',
        'updateCoordinationItem',
        'remindCoordinationItem',
        'markBeaconItemsSeen',
      });
    });
  });
}

Future<void> _rejectOrdinaryUserWritesProbe(
  FakeBeaconHierarchyRepository hierarchy,
  String beaconId,
) async {
  final status = await hierarchy.loadBeaconStatus(beaconId);
  if (status != null &&
      (status == BeaconStatus.closed ||
          status == BeaconStatus.cancelled ||
          status == BeaconStatus.deleted)) {
    throw const BeaconCreateException(
      description: 'Discussion is read-only for this request',
    );
  }
}

class FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepositoryPort {}

class FakeImageRepositoryPort extends Fake implements ImageRepositoryPort {}

class FakeTaskRepositoryPort extends Fake implements TaskRepositoryPort {}

class FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class FakePollingRepository extends Fake implements PollingRepositoryPort {}

class FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}

class PassThroughMutatingUnitOfWork extends Fake
    implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) =>
      action();
}
