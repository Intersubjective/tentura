import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_erasure_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

// More owned rows than one erasure transaction handles (batch size is 200),
// so the run is split into several committed transactions.
const _rows = 450;

void main() {
  late _World world;
  late _Erasure port;
  late UserErasureCase erasure;

  setUp(() {
    world = _World();
    port = _Erasure(world);
    erasure = UserErasureCase(
      port,
      _Beacons(),
      _Users(world),
      _Hierarchy(),
      BeaconLifecycleEffectsCase(
        _Outbox(),
        env: Env(environment: Environment.test),
        logger: Logger('UserErasureResumableChunksTest'),
      ),
      TransactionalAttentionCase(_Uow(world), _Dispatch()),
      _ImageGc(world),
      env: Env(environment: Environment.test),
      logger: Logger('UserErasureResumableChunksTest'),
    );
  });

  void seed({
    int drafts = 0,
    int deleted = 0,
    int profileImages = 0,
  }) {
    for (var i = 0; i < drafts; i++) {
      world.drafts.add('D$i');
    }
    for (var i = 0; i < deleted; i++) {
      world.deleted.add('X$i');
    }
    for (var i = 0; i < profileImages; i++) {
      world.profileImages.add('img-P$i');
    }
  }

  /// Every image whose row is gone has its cleanup job committed, and no job
  /// exists for a row that is still there.
  void expectJobsMatchDeletedImageRows() {
    expect(world.enqueued.toSet(), world.deletedImages);
    expect(world.enqueued.length, world.enqueued.toSet().length);
  }

  group('Chunked account erasure', () {
    for (final kind in ['drafts', 'deleted published Requests']) {
      group('of $kind', () {
        void seedKind() =>
            kind == 'drafts' ? seed(drafts: _rows) : seed(deleted: _rows);

        test(
          'enqueues image cleanup in the transaction that deletes the '
          'image rows of each chunk',
          () async {
            seedKind();
            world.crashAfterChunk[kind] = 2;

            await expectLater(erasure.deleteById(id: 'acct'), throwsStateError);

            // Chunk 2 rolled back as a whole: neither its image deletion nor
            // its job persisted; chunk 1 committed both.
            expect(world.deletedImages, hasLength(200));
            expectJobsMatchDeletedImageRows();
          },
        );

        test(
          'rerun after a crash between chunks converges and queues every '
          'image object',
          () async {
            seedKind();
            world.crashBeforeChunk[kind] = 2;
            await expectLater(erasure.deleteById(id: 'acct'), throwsStateError);
            expect(world.deletedImages, hasLength(200));
            expectJobsMatchDeletedImageRows();

            world.crashBeforeChunk.clear();
            expect(await erasure.deleteById(id: 'acct'), isTrue);

            expect(world.userDeleted, isTrue);
            expect(world.drafts, isEmpty);
            expect(world.deletedImages, hasLength(_rows));
            expectJobsMatchDeletedImageRows();
          },
        );
      });
    }

    test(
      'rerun after a crash in the final account step converges and keeps '
      'the cleanup jobs of earlier chunks',
      () async {
        seed(drafts: _rows, profileImages: 3);
        world.crashOnUserDelete = true;

        await expectLater(erasure.deleteById(id: 'acct'), throwsStateError);

        // Draft chunks committed (with jobs); the final step rolled back
        // together with its profile-image deletion and jobs.
        expect(world.userDeleted, isFalse);
        expect(world.profileImages, hasLength(3));
        expectJobsMatchDeletedImageRows();

        world.crashOnUserDelete = false;
        expect(await erasure.deleteById(id: 'acct'), isTrue);
        expect(world.userDeleted, isTrue);
        expect(world.profileImages, isEmpty);
        expect(world.deletedImages, hasLength(_rows + 3));
        expectJobsMatchDeletedImageRows();
      },
    );

    test(
      'final step re-lists drafts and published Requests so rows created '
      'after the first listing are erased too',
      () async {
        seed(drafts: _rows);
        world
          ..lateDraft = 'Dlate'
          ..lateDeleted = 'Xlate';

        expect(await erasure.deleteById(id: 'acct'), isTrue);

        expect(world.drafts, isEmpty);
        expect(world.deleted, isEmpty, reason: 'late Request left unscrubbed');
        expect(world.userDeleted, isTrue);
        expect(world.deletedImages, containsAll(['img-Dlate', 'img-Xlate']));
        expectJobsMatchDeletedImageRows();
      },
    );
  });
}

/// In-memory persistence with real transaction semantics: [_Uow] snapshots
/// the state on begin and restores it on rollback.
class _World {
  final drafts = <String>{};
  final deleted = <String>{};
  final profileImages = <String>{};
  final enqueued = <String>[];
  bool userDeleted = false;

  /// Images whose rows have been removed (committed state).
  final deletedImages = <String>{};

  final crashBeforeChunk = <String, int>{};
  final crashAfterChunk = <String, int>{};
  final calls = <String, int>{};
  bool crashOnUserDelete = false;
  String? lateDraft;
  String? lateDeleted;
  bool listedPublished = false;
  bool listedDrafts = false;

  _Snapshot snapshot() => _Snapshot(
    {...drafts},
    {...deleted},
    {...profileImages},
    [...enqueued],
    {...deletedImages},
    userDeleted,
  );

  void restore(_Snapshot s) {
    drafts
      ..clear()
      ..addAll(s.drafts);
    deleted
      ..clear()
      ..addAll(s.deleted);
    profileImages
      ..clear()
      ..addAll(s.profileImages);
    enqueued
      ..clear()
      ..addAll(s.enqueued);
    deletedImages
      ..clear()
      ..addAll(s.deletedImages);
    userDeleted = s.userDeleted;
  }

  void maybeCrash(Map<String, int> plan, String kind) {
    if (plan[kind] == calls[kind]) throw StateError('injected crash');
  }
}

class _Snapshot {
  _Snapshot(
    this.drafts,
    this.deleted,
    this.profileImages,
    this.enqueued,
    this.deletedImages,
    // Snapshot fields mirror _World's, in declaration order.
    // ignore: avoid_positional_boolean_parameters
    this.userDeleted,
  );

  final Set<String> drafts;
  final Set<String> deleted;
  final Set<String> profileImages;
  final List<String> enqueued;
  final Set<String> deletedImages;
  final bool userDeleted;
}

class _Uow extends Fake implements MutatingUnitOfWorkPort {
  _Uow(this.world);

  final _World world;

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async {
    final before = world.snapshot();
    try {
      return await action();
    } catch (_) {
      world.restore(before);
      rethrow;
    }
  }
}

class _Erasure extends Fake implements UserErasurePort {
  _Erasure(this.world);

  final _World world;

  @override
  Future<List<OwnedPublishedBeaconRow>> listOwnedPublishedBeacons({
    required String userId,
  }) async {
    final rows = [
      for (final id in world.deleted.toList()..sort())
        OwnedPublishedBeaconRow(beaconId: id, status: BeaconStatus.deleted),
    ];
    if (!world.listedPublished) {
      world.listedPublished = true;
      final late = world.lateDeleted;
      if (late != null) world.deleted.add(late);
    }
    return rows;
  }

  @override
  Future<List<String>> listOwnedDraftBeaconIds({required String userId}) async {
    final rows = world.drafts.toList()..sort();
    if (!world.listedDrafts) {
      world.listedDrafts = true;
      final late = world.lateDraft;
      if (late != null) world.drafts.add(late);
    }
    return rows;
  }

  @override
  Future<List<String>> scrubDeletedOwnedBeaconContents({
    required List<String> beaconIds,
    required String ownerId,
  }) async {
    const kind = 'deleted published Requests';
    world.calls[kind] = (world.calls[kind] ?? 0) + 1;
    world.maybeCrash(world.crashBeforeChunk, kind);
    final images = [for (final id in beaconIds) 'img-$id'];
    world.deleted.removeAll(beaconIds);
    world.deletedImages.addAll(images);
    world.maybeCrash(world.crashAfterChunk, kind);
    return images;
  }

  @override
  Future<List<String>> hardDeleteOwnedDraftBeacons({
    required List<String> beaconIds,
    required String ownerId,
  }) async {
    const kind = 'drafts';
    world.calls[kind] = (world.calls[kind] ?? 0) + 1;
    world.maybeCrash(world.crashBeforeChunk, kind);
    final images = [for (final id in beaconIds) 'img-$id'];
    world.drafts.removeAll(beaconIds);
    world.deletedImages.addAll(images);
    world.maybeCrash(world.crashAfterChunk, kind);
    return images;
  }

  @override
  Future<void> deleteUserScopedEvaluationAndCapabilityRows({
    required String userId,
  }) async {}

  @override
  Future<void> deleteOrdinaryRoomMessagesAuthoredByUser({
    required String userId,
  }) async {}

  @override
  Future<List<String>> deleteOwnedImageRows({required String userId}) async {
    final images = world.profileImages.toList();
    world.profileImages.clear();
    world.deletedImages.addAll(images);
    return images;
  }
}

class _Users extends Fake implements UserRepositoryPort {
  _Users(this.world);

  final _World world;

  @override
  Future<bool> deleteById({required String id}) async {
    if (world.crashOnUserDelete) throw StateError('injected crash');
    world.userDeleted = true;
    return true;
  }
}

class _ImageGc extends Fake implements ImageObjectGcPort {
  _ImageGc(this.world);

  final _World world;

  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) async {
    if (!world.enqueued.contains(imageId)) world.enqueued.add(imageId);
  }
}

class _Beacons extends Fake implements BeaconRepositoryPort {}

class _Outbox extends Fake implements BeaconHierarchyOutboxPort {}

class _Hierarchy extends Fake implements BeaconHierarchyRepositoryPort {
  @override
  Future<void> lockMutationScope() async {}
}

class _Dispatch extends Fake implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}
