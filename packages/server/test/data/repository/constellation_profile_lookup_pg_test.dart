@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' show Connection, Sql;
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// Constellation readers need only name, handle and image of each peer. The
/// lean lookup must return exactly what the public-record path returns for
/// those fields, in a single SQL statement.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_PROFILE_LOOKUP_TEST_DB',
    defaultNamePrefix: 'tentura_test_constellation_profiles',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('constellation profile lookup', () {
    const withImage = 'Uprofilelookup01';
    const withHandle = 'Uprofilelookup02';
    const blankHandle = 'Uprofilelookup03';
    const bare = 'Uprofilelookup04';
    const emptyHandle = 'Uprofilelookup05';
    const imageWithoutHandle = 'Uprofilelookup06';
    const imageSharedAuthor = 'Uprofilelookup07';
    const absent = 'Uprofilelookup99';
    const imageId = '5f1c1b0e-6c0b-4d1e-9a39-0f6a3a0a7e11';

    late DisposablePgWriterSession session;
    late Connection backend;
    late TenturaDb db;
    late _SqlRecorder sql;
    late DriftUserProfileBatchLookup lookup;

    setUpAll(() async {
      // The public-record path maps presence rows through `GetIt.I<Env>()`.
      GetIt.I.registerSingleton<Env>(Env(environment: Environment.test));
      session = await setUpDisposablePgWriter(target: target);
      backend = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      sql = _SqlRecorder();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          backend,
          enableMigrations: false,
        ).interceptWith(sql),
      );
      lookup = DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db));

      Future<void> insertUser(
        String id,
        String name, {
        String? handle,
        String? image,
      }) => session.writer.execute(
        Sql.named(
          'INSERT INTO public."user" '
          '(id, display_name, description, public_key, handle, image_id) '
          'VALUES (@id, @name, @description, @key, @handle, @image::uuid)',
        ),
        parameters: {
          'id': id,
          'name': name,
          'description': 'description of $name',
          'key': '$id-key',
          'handle': handle,
          'image': image,
        },
      );

      await insertUser(withHandle, 'Handle Holder', handle: 'handle_holder');
      await insertUser(blankHandle, 'Blank Handle', handle: '   ');
      await insertUser(bare, 'Bare Profile');
      await insertUser(emptyHandle, 'Empty Handle', handle: '');
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public.image (id, hash, height, width, author_id) '
          'VALUES (@id::uuid, @hash, 48, 64, @author)',
        ),
        parameters: {'id': imageId, 'hash': 'blurhash-1', 'author': withHandle},
      );
      await insertUser(
        withImage,
        'Image Owner',
        handle: ' padded ',
        image: imageId,
      );
      // Several users may point at one image row; the image author is a third
      // party and the owner has no handle.
      await insertUser(
        imageWithoutHandle,
        'Image Without Handle',
        image: imageId,
      );
      await insertUser(
        imageSharedAuthor,
        'Shared Image',
        handle: 'shared_image',
        image: imageId,
      );
    });

    tearDownAll(() async {
      await GetIt.I.reset();
      await backend.close();
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    setUp(() => sql.statements.clear());

    final everyone = [
      withImage,
      withHandle,
      blankHandle,
      bare,
      emptyHandle,
      imageWithoutHandle,
      imageSharedAuthor,
    ];

    test(
      'returns the same name, handle and image as the public-record path',
      () async {
        final lean = await lookup.constellationProfilesByIds(everyone);
        final full = await lookup.userPublicRecordsByIds(
          ids: everyone,
          reciprocalPeerIds: const {},
        );

        expect(lean.keys.toSet(), everyone.toSet());
        for (final id in everyone) {
          final expected = full[id]!;
          final actual = lean[id]!;
          expect(actual.id, expected.id, reason: 'id of $id');
          expect(
            actual.displayName,
            expected.displayName,
            reason: 'name of $id',
          );
          expect(actual.handle, expected.handle, reason: 'handle of $id');
          expect(actual.image?.id, expected.image?.id, reason: 'image of $id');
          expect(
            actual.image?.hash,
            expected.image?.hash,
            reason: 'hash of $id',
          );
          expect(
            actual.image?.height,
            expected.image?.height,
            reason: 'height of $id',
          );
          expect(
            actual.image?.width,
            expected.image?.width,
            reason: 'width of $id',
          );
          expect(
            actual.image?.authorId,
            expected.image?.authorId,
            reason: 'image author of $id',
          );
          expect(
            actual.image?.createdAt,
            expected.image?.createdAt,
            reason: 'image createdAt of $id',
          );
        }
      },
    );

    test(
      'trims handles, maps blank handles to null and carries image fields',
      () async {
        final lean = await lookup.constellationProfilesByIds(everyone);

        expect(lean[withImage]!.handle, 'padded');
        expect(lean[blankHandle]!.handle, isNull);
        expect(lean[bare]!.handle, isNull);
        expect(lean[emptyHandle]!.handle, isNull);
        expect(lean[imageWithoutHandle]!.handle, isNull);
        expect(lean[imageWithoutHandle]!.image?.id, imageId);
        expect(lean[imageSharedAuthor]!.handle, 'shared_image');
        expect(lean[imageSharedAuthor]!.image?.id, imageId);
        expect(lean[bare]!.image, isNull);
        final image = lean[withImage]!.image!;
        expect(image.id, imageId);
        expect(image.hash, 'blurhash-1');
        expect(image.height, 48);
        expect(image.width, 64);
        expect(image.authorId, withHandle);
      },
    );

    test('omits unknown ids and ignores empty and duplicate ids', () async {
      final lean = await lookup.constellationProfilesByIds([
        bare,
        bare,
        '',
        absent,
      ]);

      expect(lean.keys, [bare]);
    });

    test('issues exactly one SQL statement for a batch of profiles', () async {
      await lookup.constellationProfilesByIds(everyone);

      expect(sql.statements, hasLength(1), reason: sql.statements.join('\n'));
      expect(sql.statements.single, _isSingleReadStatement);
    });

    test(
      'issues exactly one SQL statement even when no profile has an image',
      () async {
        await lookup.constellationProfilesByIds([bare, blankHandle]);

        expect(sql.statements, hasLength(1), reason: sql.statements.join('\n'));
        expect(sql.statements.single, _isSingleReadStatement);
      },
    );

    test('issues no SQL statement for an empty id set', () async {
      final lean = await lookup.constellationProfilesByIds(const <String>[]);

      expect(lean, isEmpty);
      expect(sql.statements, isEmpty);
    });

    test(
      'field repository peer profiles come from a single statement',
      () async {
        final fields = ConstellationFieldRepository(db, lookup);

        final peers = await fields.peerProfiles(ids: everyone.toSet());

        expect(sql.statements, hasLength(1), reason: sql.statements.join('\n'));
        expect(peers.map((p) => p.id).toSet(), everyone.toSet());
        expect(peers, hasLength(everyone.length));
        final owner = peers.singleWhere((p) => p.id == withImage);
        expect(owner.displayName, 'Image Owner');
        expect(owner.handle, 'padded');
        expect(owner.image?.hash, 'blurhash-1');
      },
    );
  }, skip: skipReason);
}

/// A lone SELECT (or WITH ... SELECT): no second statement smuggled in.
final _isSingleReadStatement = predicate<String>((statement) {
  final text = statement.trim().replaceAll(RegExp(r';\s*$'), '').toLowerCase();
  return (text.startsWith('select') || text.startsWith('with')) &&
      !text.contains(';');
}, 'a single SELECT statement');

/// Records every statement that reaches the executor, whichever Drift entry
/// point issued it (`customSelect` goes through `runSelect`, but custom
/// statements, inserts and updates use other hooks).
final class _SqlRecorder extends QueryInterceptor {
  final statements = <String>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runDelete(executor, statement, args);
  }
}
