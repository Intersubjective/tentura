import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_child_create_port.dart';
import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/noop_commitment_query_case.dart';

class _StubBeaconRepo extends Fake implements BeaconRepositoryPort {
  Future<BeaconEntity> Function()? onGetBeaconById;
  Future<BeaconEntity> Function()? onPublishDraft;
  int publishDraftCalls = 0;

  /// What createBeacon / updateDraftBeacon were asked to persist.
  final created = <({String description, BeaconStatus? status})>[];
  final updatedDrafts = <({String beaconId, String description})>[];

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async => 0;

  @override
  Future<BeaconEntity> createBeacon({
    required String authorId,
    required String title,
    String? description,
    String? context,
    List<String>? imageIds,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    Set<String>? tags,
    Set<String>? needs,
    int ticker = 0,
    String? primaryNeedSlug,
    String? coverImageId,
    BeaconCoverSource coverSource = BeaconCoverSource.photo,
    BeaconStatus? status,
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
    bool? isDiscoverable,
    BeaconKind kind = BeaconKind.request,
    BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
    String? clientOpId,
  }) async {
    created.add((description: description ?? '', status: status));
    return BeaconEntity(
      id: 'Bnew',
      title: title,
      description: description ?? '',
      author: UserEntity(id: authorId),
      createdAt: DateTime.utc(2026, 6, 18),
      updatedAt: DateTime.utc(2026, 6, 18),
      status: status ?? BeaconStatus.open,
    );
  }

  @override
  Future<BeaconEntity> updateDraftBeacon({
    required String beaconId,
    required String userId,
    required String title,
    required String description,
    String? context,
    Set<String>? tags,
    Set<String>? needs,
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? primaryNeedSlug,
    String? addressLabel,
    bool? isDiscoverable,
    bool isDiscoverableProvided = false,
  }) async {
    updatedDrafts.add((beaconId: beaconId, description: description));
    return BeaconEntity(
      id: beaconId,
      title: title,
      description: description,
      author: UserEntity(id: userId),
      createdAt: DateTime.utc(2026, 6, 18),
      updatedAt: DateTime.utc(2026, 6, 18),
      status: BeaconStatus.draft,
    );
  }

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) =>
      onGetBeaconById!();

  @override
  Future<BeaconEntity> publishDraft({
    required String id,
    required String actorId,
  }) {
    publishDraftCalls++;
    return onPublishDraft!();
  }
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

void main() {
  late _StubBeaconRepo beaconRepo;
  late BeaconCase case_;
  final now = DateTime.utc(2026, 6, 18);

  BeaconEntity draftBeacon({String description = 'Draft description'}) =>
      BeaconEntity(
        id: 'Bdraft',
        title: 'Draft title',
        description: description,
        author: const UserEntity(id: 'Uauth'),
        createdAt: now,
        updatedAt: now,
        status: BeaconStatus.draft,
      );

  setUp(() {
    beaconRepo = _StubBeaconRepo();
    case_ = BeaconCase(
      beaconRepo,
      _FakeImageRepo(),
      _FakeImageObjectGc(),
      _FakeTaskRepo(),
      noopCommitmentQueryCase(),
      FakeBeaconAccessGuard(),
      FakeBeaconHierarchyRepository(),
      FakeBeaconChildCreatePort(),
      buildLifecycleEffectsCase(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCasePublishDraftTest'),
    );
  });

  test('publishDraft delegates to repository for valid draft', () async {
    final beacon = draftBeacon();
    final published = beacon.copyWith(status: BeaconStatus.open);
    beaconRepo.onGetBeaconById = () async => beacon;
    beaconRepo.onPublishDraft = () async => published;

    final result = await case_.publishDraft(
      userId: 'Uauth',
      beaconId: beacon.id,
    );

    expect(result.status, BeaconStatus.open);
    expect(beaconRepo.publishDraftCalls, 1);
  });

  // #340: a draft may be saved without a description; publishing asks for one.
  test('publishDraft refuses a Request draft without a description', () async {
    beaconRepo.onGetBeaconById = () async => draftBeacon(description: ' ');

    await expectLater(
      case_.publishDraft(userId: 'Uauth', beaconId: 'Bdraft'),
      throwsA(
        isA<BeaconCreateException>().having(
          (e) => e.description,
          'description',
          'Description is required',
        ),
      ),
    );
    expect(beaconRepo.publishDraftCalls, 0);
  });

  // #340 as reported: Save draft on a Request with only a title. The use
  // cases must hand the draft rule on, so the save reaches the repository.
  test('saving a new title-only Request draft is persisted', () async {
    final draft = await case_.create(
      userId: 'Uauth',
      title: 'Title only',
      draft: true,
    );

    expect(draft.status, BeaconStatus.draft);
    expect(beaconRepo.created, [(description: '', status: BeaconStatus.draft)]);
  });

  test('updating a draft to an empty description is persisted', () async {
    await case_.updateDraft(
      userId: 'Uauth',
      beaconId: 'Bdraft',
      title: 'Draft title',
      description: '  ',
    );

    expect(beaconRepo.updatedDrafts, [(beaconId: 'Bdraft', description: '')]);
  });

  test('publishing a new Request still needs a description', () async {
    await expectLater(
      case_.create(userId: 'Uauth', title: 'Title only'),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(beaconRepo.created, isEmpty);
  });
}
