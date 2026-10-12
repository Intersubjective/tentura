@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_erasure_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/user_erasure_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

// More owned rows than one erasure transaction handles (batch size is 200).
const _ownedRows = 450;

/// Account erasure over many rows runs as several committed transactions. A
/// crash between (or inside) them must leave a state that a plain rerun of
/// the erasure completes, with every removed image row's object queued for
/// storage cleanup and nothing queued for a row that still exists.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_ERASURE_RESUMABLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_erasureres',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('Chunked account erasure against Postgres', () {
    late Connection writer;
    late TenturaDb database;
    late _Injecting erasurePort;
    late _InjectingGc imageGc;
    late UserErasureRepository erasureRepository;
    late _CrashingUsers users;
    late UserErasureCase erasure;
    var seq = 0;

    setUpAll(() async {
      if (skipReason != false) return;
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      final env = Env(environment: Environment.test);
      final logger = Logger('UserErasureResumableChunksPgTest');
      erasureRepository = UserErasureRepository(database);
      erasurePort = _Injecting(erasureRepository, () async {
        // Another session can take the hierarchy mutation lock only when the
        // erasing transaction does not hold it.
        final got = await writer.execute(
          'SELECT pg_try_advisory_lock(hashtextextended( '
          "'tentura.beacon_hierarchy.v1', 0))",
        );
        final free = got.single.single! as bool;
        if (free) {
          await writer.execute(
            'SELECT pg_advisory_unlock(hashtextextended( '
            "'tentura.beacon_hierarchy.v1', 0))",
          );
        }
        return free;
      });
      imageGc = _InjectingGc(ImageObjectGcRepository(database, _NoRemoteStorage()));
      users = _CrashingUsers(env, database);
      erasure = UserErasureCase(
        erasurePort,
        BeaconRepository(database),
        users,
        BeaconHierarchyRepository(database),
        BeaconLifecycleEffectsCase(
          BeaconHierarchyOutboxRepository(database),
          env: env,
          logger: logger,
        ),
        TransactionalAttentionCase(
          MutatingUnitOfWork(database),
          AttentionDispatchRepository(database, logger),
        ),
        imageGc,
        env: env,
        logger: logger,
      );
    });

    setUp(() {
      erasurePort.reset();
      imageGc.reset();
      users.crashOnDelete = false;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await database.close();
      await writer.close();
      await target.drop();
    });

    Future<String> seedUser() async {
      final id = 'Uerres${(seq++).toString().padLeft(6, '0')}';
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': id, 'key': 'erasure-resumable-key-$id'},
      );
      return id;
    }

    /// Inserts a beacon with a cover image; returns the image id.
    Future<String> seedBeacon(
      String userId,
      String beaconId,
      BeaconStatus status, {
      required bool published,
    }) async {
      final image = await writer.execute(
        Sql.named(
          'INSERT INTO public.image (author_id) VALUES (@a) RETURNING id::text',
        ),
        parameters: {'a': userId},
      );
      final imageId = image.single.single! as String;
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES (@id, @user, 't', 'd', @status, ${published ? 'now()' : 'NULL'})
'''),
        parameters: {
          'id': beaconId,
          'user': userId,
          'status': status.smallintValue,
        },
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_image (beacon_id, image_id) '
          'VALUES (@id, @image::uuid)',
        ),
        parameters: {'id': beaconId, 'image': imageId},
      );
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon SET cover_image_id = @image::uuid WHERE id = @id',
        ),
        parameters: {'id': beaconId, 'image': imageId},
      );
      return imageId;
    }

    Future<Set<String>> imagesOf(String userId) async => {
      for (final r in await writer.execute(
        Sql.named('SELECT id::text FROM public.image WHERE author_id = @a'),
        parameters: {'a': userId},
      ))
        r.single! as String,
    };

    Future<Set<String>> queued(Set<String> ids) async => {
      for (final r in await writer.execute(
        'SELECT image_id::text FROM public.image_object_gc',
      ))
        if (ids.contains(r.single)) r.single! as String,
    };

    Future<bool> userExists(String id) async =>
        (await writer.execute(
              Sql.named('SELECT 1 FROM public."user" WHERE id = @id'),
              parameters: {'id': id},
            ))
            .isNotEmpty;

    /// Creates an image authored by [userId] and makes it the user's avatar.
    Future<String> seedAvatar(String userId) async {
      final image = await writer.execute(
        Sql.named(
          'INSERT INTO public.image (author_id) VALUES (@a) RETURNING id::text',
        ),
        parameters: {'a': userId},
      );
      final imageId = image.single.single! as String;
      await writer.execute(
        Sql.named(
          'UPDATE public."user" SET image_id = @image::uuid WHERE id = @id',
        ),
        parameters: {'id': userId, 'image': imageId},
      );
      return imageId;
    }

    Future<void> seedDrafts(String userId, Set<String> images) async {
      for (var i = 0; i < _ownedRows; i++) {
        images.add(
          await seedBeacon(
            userId,
            'Bd$userId$i',
            BeaconStatus.draft,
            published: false,
          ),
        );
      }
    }

    test(
      'a small account whose avatar is set is erased and the avatar object '
      'is queued for storage cleanup',
      () async {
        final user = await seedUser();
        final avatar = await seedAvatar(user);
        final cover = await seedBeacon(
          user,
          'Bd${user}0',
          BeaconStatus.draft,
          published: false,
        );

        expect(await erasure.deleteById(id: user), isTrue);

        expect(await userExists(user), isFalse);
        expect(await imagesOf(user), isEmpty);
        expect(await queued({avatar, cover}), {avatar, cover});
      },
    );

    test(
      'a chunked account whose avatar is set is erased and the avatar '
      'object is queued for storage cleanup',
      () async {
        final user = await seedUser();
        final images = <String>{};
        await seedDrafts(user, images);
        final avatar = await seedAvatar(user);
        images.add(avatar);

        expect(await erasure.deleteById(id: user), isTrue);

        expect(await userExists(user), isFalse);
        expect(await imagesOf(user), isEmpty);
        expect(await queued(images), images);
      },
    );

    for (final atomic in [true, false]) {
      test(
        'a ${atomic ? 'small' : 'chunked'} account with an avatar rolls '
        'the whole final step back when the user deletion fails, and a '
        'rerun completes',
        () async {
          final user = await seedUser();
          final images = <String>{};
          if (!atomic) await seedDrafts(user, images);
          final avatar = await seedAvatar(user);
          images.add(avatar);

          users.crashOnDelete = true;
          await expectLater(erasure.deleteById(id: user), throwsStateError);

          // Neither the avatar reference, the image row nor its cleanup job
          // survive a partial final step.
          expect(await userExists(user), isTrue);
          expect(await imagesOf(user), contains(avatar));
          expect(
            (await writer.execute(
              Sql.named('SELECT image_id::text FROM public."user" WHERE id = @id'),
              parameters: {'id': user},
            )).single.single,
            avatar,
          );
          expect(await queued({avatar}), isEmpty);

          users.crashOnDelete = false;
          expect(await erasure.deleteById(id: user), isTrue);
          expect(await userExists(user), isFalse);
          expect(await queued(images), images);
        },
      );
    }

    test(
      'a failure of the avatar cleanup job insert rolls back the final step '
      'and a rerun queues the avatar once',
      () async {
        final user = await seedUser();
        final avatar = await seedAvatar(user);

        imageGc.crashAfterEnqueue = 1;
        await expectLater(erasure.deleteById(id: user), throwsStateError);

        expect(await userExists(user), isTrue);
        expect(await imagesOf(user), contains(avatar));
        expect(await queued({avatar}), isEmpty);

        imageGc.reset();
        expect(await erasure.deleteById(id: user), isTrue);
        expect(await userExists(user), isFalse);
        expect(await queued({avatar}), {avatar});
      },
    );

    test(
      'rerun after a crash following a committed draft chunk erases '
      'everything and queues every image object',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bd$user$i',
              BeaconStatus.draft,
              published: false,
            ),
          );
        }
        erasurePort.crashBeforeDraftChunk = 2;
        await expectLater(erasure.deleteById(id: user), throwsStateError);

        // Chunk one committed: its image rows are gone, so the matching
        // cleanup jobs must already be durable.
        final remaining = await imagesOf(user);
        expect(remaining.length, lessThan(images.length));
        expect(await queued(images), images.difference(remaining));

        erasurePort.reset();
        expect(await erasure.deleteById(id: user), isTrue);

        expect(await userExists(user), isFalse);
        expect(await queued(images), images);
      },
    );

    test(
      'a draft chunk that fails after deleting its rows leaves neither '
      'the image deletion nor its cleanup jobs behind',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bd$user$i',
              BeaconStatus.draft,
              published: false,
            ),
          );
        }
        erasurePort.crashAfterDraftChunk = 2;
        await expectLater(erasure.deleteById(id: user), throwsStateError);

        final remaining = await imagesOf(user);
        final goneImages = images.difference(remaining);
        // Only the first (committed) chunk's rows are gone, and exactly
        // those are queued: the rolled-back chunk left no orphan job and
        // did not lose its image rows without a job.
        expect(goneImages, hasLength(200));
        expect(await queued(images), goneImages);

        erasurePort.reset();
        expect(await erasure.deleteById(id: user), isTrue);
        expect(await queued(images), images);
      },
    );

    test(
      'rerun after a crash in the final account step converges and keeps '
      'the cleanup jobs of earlier chunks',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bd$user$i',
              BeaconStatus.draft,
              published: false,
            ),
          );
        }
        final profile = await writer.execute(
          Sql.named(
            'INSERT INTO public.image (author_id) VALUES (@a) RETURNING id::text',
          ),
          parameters: {'a': user},
        );
        images.add(profile.single.single! as String);

        users.crashOnDelete = true;
        await expectLater(erasure.deleteById(id: user), throwsStateError);
        // The final step rolled back as a whole: user and profile image
        // remain, and no job is queued for the rolled-back image deletion.
        expect(await userExists(user), isTrue);
        expect(await imagesOf(user), contains(profile.single.single));
        expect(await queued({profile.single.single! as String}), isEmpty);

        users.crashOnDelete = false;
        expect(await erasure.deleteById(id: user), isTrue);
        expect(await userExists(user), isFalse);
        expect(await queued(images), images);
      },
    );

    test(
      'rerun after a crash following a committed deleted-Request chunk '
      'converges and queues every image object',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bx$user$i',
              BeaconStatus.deleted,
              published: true,
            ),
          );
        }
        erasurePort.crashBeforeDeletedChunk = 2;
        await expectLater(erasure.deleteById(id: user), throwsStateError);
        expect(
          await queued(images),
          images.difference(await imagesOf(user)),
        );
        expect(await queued(images), isNotEmpty);

        erasurePort.reset();
        expect(await erasure.deleteById(id: user), isTrue);
        expect(await userExists(user), isFalse);
        expect(await queued(images), images);
      },
    );

    test(
      'rerun after a crash following committed per-Request transitions '
      'converges and queues every image object',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bo$user$i',
              BeaconStatus.open,
              published: true,
            ),
          );
        }
        erasurePort.crashBeforeScrub = 3;
        await expectLater(erasure.deleteById(id: user), throwsStateError);
        expect(
          await queued(images),
          images.difference(await imagesOf(user)),
        );
        expect(await queued(images), hasLength(2));

        erasurePort.reset();
        expect(await erasure.deleteById(id: user), isTrue);
        expect(await userExists(user), isFalse);
        expect(await queued(images), images);
      },
    );

    test(
      'a published Request created after the first listing is erased by '
      'the final step',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bd$user$i',
              BeaconStatus.draft,
              published: false,
            ),
          );
        }
        final lateId = 'Blate$user';
        late final String lateImage;
        erasurePort.afterFirstPublishedListing = () async {
          lateImage = await seedBeacon(
            user,
            lateId,
            BeaconStatus.open,
            published: true,
          );
        };

        expect(await erasure.deleteById(id: user), isTrue);

        final row = (await writer.execute(
          Sql.named(
            'SELECT status, cover_image_id, user_id FROM public.beacon '
            'WHERE id = @id',
          ),
          parameters: {'id': lateId},
        )).single;
        expect(row[0], BeaconStatus.deleted.smallintValue);
        expect(row[1], isNull, reason: 'late Request content is scrubbed');
        expect(row[2], isNull, reason: 'late Request is detached from user');
        expect(await userExists(user), isFalse);
        expect(await queued({lateImage}), {lateImage});
        expect(await queued(images), images);
      },
    );

    test(
      'the repository removes the image rows of a draft chunk it deletes',
      () async {
        final user = await seedUser();
        final images = <String>{};
        final ids = <String>[];
        for (var i = 0; i < 3; i++) {
          ids.add('Bd$user$i');
          images.add(
            await seedBeacon(
              user,
              ids.last,
              BeaconStatus.draft,
              published: false,
            ),
          );
        }

        final removed = await erasureRepository.hardDeleteOwnedDraftBeacons(
          beaconIds: ids,
          ownerId: user,
        );

        expect(removed.toSet(), images);
        expect(await imagesOf(user), isEmpty);
      },
    );

    for (final failure in ['before', 'after']) {
      test(
        'a failure $failure the cleanup job insert of a chunk rolls back '
        "that chunk's image-row deletion too",
        () async {
          final user = await seedUser();
          final images = <String>{};
          for (var i = 0; i < _ownedRows; i++) {
            images.add(
              await seedBeacon(
                user,
                'Bd$user$i',
                BeaconStatus.draft,
                published: false,
              ),
            );
          }
          if (failure == 'before') {
            imageGc.crashBeforeEnqueue = 1;
          } else {
            imageGc.crashAfterEnqueue = 1;
          }

          await expectLater(erasure.deleteById(id: user), throwsStateError);

          // The very first chunk's job insert failed; if the job were
          // written in a separate transaction from the row deletion, the
          // rows would be gone without a job (or a job without a row
          // deletion). In one transaction neither happened.
          expect(await imagesOf(user), images);
          expect(await queued(images), isEmpty);

          imageGc.reset();
          expect(await erasure.deleteById(id: user), isTrue);
          expect(await queued(images), images);
        },
      );
    }

    test(
      'a deleted-Request chunk that fails after deleting its rows leaves '
      'neither the image deletion nor its cleanup jobs behind',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bx$user$i',
              BeaconStatus.deleted,
              published: true,
            ),
          );
        }
        erasurePort.crashAfterDeletedChunk = 2;
        await expectLater(erasure.deleteById(id: user), throwsStateError);

        final gone = images.difference(await imagesOf(user));
        expect(gone, hasLength(200));
        expect(await queued(images), gone);

        erasurePort.reset();
        expect(await erasure.deleteById(id: user), isTrue);
        expect(await userExists(user), isFalse);
        expect(await queued(images), images);
      },
    );

    test(
      'a draft created after the first listing is erased by the final step',
      () async {
        final user = await seedUser();
        final images = <String>{};
        for (var i = 0; i < _ownedRows; i++) {
          images.add(
            await seedBeacon(
              user,
              'Bd$user$i',
              BeaconStatus.draft,
              published: false,
            ),
          );
        }
        late final String lateImage;
        erasurePort.afterFirstDraftListing = () async {
          lateImage = await seedBeacon(
            user,
            'Bdlate$user',
            BeaconStatus.draft,
            published: false,
          );
        };

        expect(await erasure.deleteById(id: user), isTrue);

        expect(
          await writer.execute(
            Sql.named('SELECT 1 FROM public.beacon WHERE id = @id'),
            parameters: {'id': 'Bdlate$user'},
          ),
          isEmpty,
        );
        expect(await userExists(user), isFalse);
        expect(await queued({lateImage}), {lateImage});
        expect(await queued(images), images);
      },
    );

    test(
      'the final step re-lists owned Requests while holding the mutation '
      'lock, so none can be created between listing and deletion',
      () async {
        final user = await seedUser();
        for (var i = 0; i < _ownedRows; i++) {
          await seedBeacon(
            user,
            'Bd$user$i',
            BeaconStatus.draft,
            published: false,
          );
        }

        expect(await erasure.deleteById(id: user), isTrue);

        // Each listing after the initial one is the final-step re-list.
        expect(erasurePort.relistLockFree, isNotEmpty);
        expect(
          erasurePort.relistLockFree,
          everyElement(isFalse),
          reason: 'a re-list ran without the mutation lock held',
        );
      },
    );
  }, skip: skipReason);
}

/// Delegates to the real repository and injects failures at chosen calls.
class _Injecting implements UserErasurePort {
  _Injecting(this._inner, this._lockIsFree);

  final Future<bool> Function() _lockIsFree;

  final UserErasurePort _inner;

  int? crashBeforeDraftChunk;
  int? crashAfterDraftChunk;
  int? crashBeforeDeletedChunk;
  int? crashAfterDeletedChunk;
  Future<void> Function()? afterFirstDraftListing;
  final relistLockFree = <bool>[];
  int _publishedListings = 0;
  int _draftListings = 0;
  int? crashBeforeScrub;
  Future<void> Function()? afterFirstPublishedListing;

  int _draft = 0;
  int _deleted = 0;
  int _scrub = 0;
  bool _listed = false;

  void reset() {
    crashBeforeDraftChunk = null;
    crashAfterDraftChunk = null;
    crashBeforeDeletedChunk = null;
    crashAfterDeletedChunk = null;
    afterFirstDraftListing = null;
    relistLockFree.clear();
    _publishedListings = _draftListings = 0;
    crashBeforeScrub = null;
    afterFirstPublishedListing = null;
    _draft = _deleted = _scrub = 0;
    _listed = false;
  }

  @override
  Future<List<OwnedPublishedBeaconRow>> listOwnedPublishedBeacons({
    required String userId,
  }) async {
    if (++_publishedListings > 1) relistLockFree.add(await _lockIsFree());
    final rows = await _inner.listOwnedPublishedBeacons(userId: userId);
    if (!_listed) {
      _listed = true;
      await afterFirstPublishedListing?.call();
    }
    return rows;
  }

  @override
  Future<List<String>> listOwnedDraftBeaconIds({required String userId}) async {
    if (++_draftListings > 1) relistLockFree.add(await _lockIsFree());
    final rows = await _inner.listOwnedDraftBeaconIds(userId: userId);
    if (_draftListings == 1) await afterFirstDraftListing?.call();
    return rows;
  }

  @override
  Future<List<String>> scrubDeletedOwnedBeaconContent({
    required String beaconId,
    required String ownerId,
  }) async {
    if (crashBeforeScrub == ++_scrub) throw StateError('injected crash');
    return _inner.scrubDeletedOwnedBeaconContent(
      beaconId: beaconId,
      ownerId: ownerId,
    );
  }

  @override
  Future<List<String>> hardDeleteOwnedDraftBeacon({
    required String beaconId,
    required String ownerId,
  }) => _inner.hardDeleteOwnedDraftBeacon(beaconId: beaconId, ownerId: ownerId);

  @override
  Future<List<String>> scrubDeletedOwnedBeaconContents({
    required List<String> beaconIds,
    required String ownerId,
  }) async {
    if (crashBeforeDeletedChunk == ++_deleted) {
      throw StateError('injected crash');
    }
    final images = await _inner.scrubDeletedOwnedBeaconContents(
      beaconIds: beaconIds,
      ownerId: ownerId,
    );
    if (crashAfterDeletedChunk == _deleted) throw StateError('injected crash');
    return images;
  }

  @override
  Future<List<String>> hardDeleteOwnedDraftBeacons({
    required List<String> beaconIds,
    required String ownerId,
  }) async {
    _draft++;
    if (crashBeforeDraftChunk == _draft) throw StateError('injected crash');
    final images = await _inner.hardDeleteOwnedDraftBeacons(
      beaconIds: beaconIds,
      ownerId: ownerId,
    );
    if (crashAfterDraftChunk == _draft) throw StateError('injected crash');
    return images;
  }

  @override
  Future<void> deleteUserScopedEvaluationAndCapabilityRows({
    required String userId,
  }) => _inner.deleteUserScopedEvaluationAndCapabilityRows(userId: userId);

  @override
  Future<void> deleteOrdinaryRoomMessagesAuthoredByUser({
    required String userId,
  }) => _inner.deleteOrdinaryRoomMessagesAuthoredByUser(userId: userId);

  @override
  Future<List<String>> deleteOwnedImageRows({required String userId}) =>
      _inner.deleteOwnedImageRows(userId: userId);
}

class _CrashingUsers extends UserRepository {
  _CrashingUsers(Env env, TenturaDb database)
    : super(
        env,
        database,
        _NoopInvites(),
        InviteSeedPromptRepositoryMock(),
      );

  bool crashOnDelete = false;

  @override
  Future<void> deleteById({required String id}) {
    if (crashOnDelete) throw StateError('injected crash');
    return super.deleteById(id: id);
  }
}

class _NoopInvites extends Fake implements InviteGenealogyRepositoryPort {}

class _NoRemoteStorage extends Fake implements RemoteStoragePort {}

/// Delegates to the real GC outbox and injects failures at chosen enqueues.
class _InjectingGc implements ImageObjectGcPort {
  _InjectingGc(this._inner);

  final ImageObjectGcPort _inner;
  int? crashBeforeEnqueue;
  int? crashAfterEnqueue;
  int _enqueues = 0;

  void reset() {
    crashBeforeEnqueue = crashAfterEnqueue = null;
    _enqueues = 0;
  }

  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) async {
    _enqueues++;
    if (crashBeforeEnqueue == _enqueues) throw StateError('injected crash');
    await _inner.enqueue(imageId: imageId, authorId: authorId);
    if (crashAfterEnqueue == _enqueues) throw StateError('injected crash');
  }

  @override
  Future<void> removeObject({
    required String imageId,
    required String authorId,
  }) => _inner.removeObject(imageId: imageId, authorId: authorId);

  @override
  Future<List<ImageObjectGcLease>> claim({
    required String leaseOwner,
    required DateTime now,
    int limit = 32,
  }) => _inner.claim(leaseOwner: leaseOwner, now: now, limit: limit);

  @override
  Future<bool> complete({
    required String imageId,
    required String leaseOwner,
  }) => _inner.complete(imageId: imageId, leaseOwner: leaseOwner);

  @override
  Future<bool> fail({
    required String imageId,
    required String leaseOwner,
    required DateTime retryAt,
    required String error,
  }) => _inner.fail(
    imageId: imageId,
    leaseOwner: leaseOwner,
    retryAt: retryAt,
    error: error,
  );
}
