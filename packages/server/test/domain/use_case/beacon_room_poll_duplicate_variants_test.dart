import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
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

const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => true;

  @override
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async => 0;

  @override
  Future<Map<String, Object?>> insertAndEnrichPollMessage({
    required String beaconId,
    required String authorId,
    required String linkedPollingId,
    required String viewerUserId,
  }) async => {'id': 'Raaaaaaaaaaaa'};
}

class _RecordingPolling extends Fake implements PollingRepositoryPort {
  int created = 0;

  @override
  Future<String> createWithVariants({
    required String authorId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) async {
    created++;
    return 'Pollaaaaaaaaa';
  }
}

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakeQuota extends Fake implements UploadQuotaRepositoryPort {}

void main() {
  late _RecordingPolling polling;
  late BeaconRoomCase sut;

  setUp(() {
    polling = _RecordingPolling();
    sut = BeaconRoomCase(
      _StubRoom(),
      _FakeItems(),
      _FakeFactCards(),
      _FakeImages(),
      _FakeTasks(),
      _FakeRemoteStorage(),
      polling,
      _FakeQuota(),
      FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomPollDuplicateVariantsTest'),
    );
  });

  Future<Map<String, Object?>> create(List<String> variants) =>
      sut.createPoll(
        beaconId: _beaconId,
        userId: _userId,
        question: 'Which?',
        variants: variants,
      );

  test('exact duplicate options throw a typed error, no insert', () async {
    await expectLater(
      create(['Same', 'Same']),
      throwsA(isA<PollDuplicateVariantException>()),
    );
    expect(polling.created, 0);
  });

  test('case / whitespace-normalised duplicates are rejected', () async {
    await expectLater(
      create(['Same  thing', 'a', ' same THING ']),
      throwsA(isA<PollDuplicateVariantException>()),
    );
    expect(polling.created, 0);
  });

  test('distinct options still create the poll', () async {
    final r = await create(['One', 'Two']);
    expect(r['id'], 'Raaaaaaaaaaaa');
    expect(polling.created, 1);
  });
}
