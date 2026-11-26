@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:image/image.dart' as image;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/person_subject.dart';
import 'package:tentura_server/domain/port/private_avatar_repository_port.dart';
import 'package:tentura_server/domain/port/private_object_gc_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Ua7a7a0000001';
const _otherOwner = 'Ua7a7a0000002';
const _account = 'Ua7a7a0000003';
const _otherAccount = 'Ua7a7a0000004';
const _thirdAccount = 'Ua7a7a0000005';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_AVATAR_LINKING_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_avatar_link',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Private avatars when linking a Field entry to an account', () {
    late _Fixture fixture;
    final storage = _MemoryStorage();

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      getIt.registerSingleton<RemoteStoragePort>(storage);
      await configureSessionDatabaseTestGraph(target.databaseEnv);
      final router = await getIt.getAsync<RootRouter>();
      fixture = _Fixture(session.writer, router.routeHandler());
    });

    setUp(() async {
      storage.objects.clear();
      await fixture.reset();
    });

    test(
      'copies the image and records it for undo only when the owner has no account avatar',
      () async {
        final withImage = await fixture.entry();
        final withExistingAccountImage = await fixture.entry();
        final withoutImage = await fixture.entry();
        final source = await fixture.upload(withImage);
        final otherSource = await fixture.upload(withExistingAccountImage);
        const existingAccount = PersonSubject.user(_otherAccount);
        final existing = await fixture.upload(
          existingAccount,
          red: 40,
        );
        expect(
          await fixture.avatars(const PersonSubject.user(_account)),
          isEmpty,
        );

        final copiedMerge = await fixture.link(withImage);
        final keptMerge = await fixture.link(
          withExistingAccountImage,
          user: _otherAccount,
        );
        await fixture.link(withoutImage, user: _thirdAccount);

        expect(await fixture.avatars(withImage), [source]);
        expect(await fixture.avatars(withExistingAccountImage), [otherSource]);
        expect(await fixture.avatars(existingAccount), [existing]);
        expect(
          await fixture.avatars(const PersonSubject.user(_thirdAccount)),
          isEmpty,
        );
        expect(
          await fixture.queuedKeys([otherSource.objectKey, existing.objectKey]),
          isEmpty,
        );
        expect(
          await fixture.avatarUndo(keptMerge, user: _otherAccount),
          isNull,
        );
        await fixture.undo(withExistingAccountImage, keptMerge);
        expect(
          await fixture.avatars(existingAccount),
          [existing],
          reason: 'Unlink must preserve the original account row and its key.',
        );
        expect(
          await fixture.queuedKeys([existing.objectKey]),
          isEmpty,
          reason:
              'Unlink must leave the original account key out of the queue.',
        );
        expect(
          await fixture.avatarUndo(copiedMerge, user: _account),
          isA<Map<String, Object?>>()
              .having((avatar) => avatar['subjectUserId'], 'account', _account)
              .having((avatar) => avatar['objectKey'], 'key', source.objectKey)
              .having(
                (avatar) => avatar['subjectPhantomId'],
                'private entry',
                isNull,
              ),
          reason: 'Undo must identify the newly inserted account avatar.',
        );
        expect(
          await fixture.avatars(const PersonSubject.user(_account)),
          [_copyOnAccount(source)],
        );
      },
    );

    test(
      'copies the owner’s avatar and image metadata alongside another owner’s avatar',
      () async {
        final entry = await fixture.entry();
        const account = PersonSubject.user(_account);
        final source = await fixture.upload(entry);
        final other = await fixture.upload(
          account,
          owner: _otherOwner,
          red: 40,
        );

        await fixture.link(entry);

        expect(await fixture.avatars(account, owner: _otherOwner), [other]);
        expect(await fixture.avatars(entry), [source]);
        expect(await fixture.avatars(account), [_copyOnAccount(source)]);
      },
    );

    test(
      'undo removes the account copy and preserves the image referenced by the original entry',
      () async {
        final entry = await fixture.entry();
        const account = PersonSubject.user(_account);
        final jpeg = _jpeg();
        final source = await fixture.upload(entry, bytes: jpeg);
        final otherOwner = await fixture.upload(
          account,
          owner: _otherOwner,
          red: 90,
        );

        final mergeId = await fixture.link(entry);
        final linkedAvatars = await fixture.avatars(account);
        await fixture.undo(entry, mergeId);

        expect(
          await fixture.avatars(account),
          isEmpty,
          reason: 'Undo must delete the account row created by linking.',
        );
        expect(
          await fixture.avatars(entry),
          [source],
          reason: 'Undo must preserve the source row and its key.',
        );
        expect(await fixture.avatars(account, owner: _otherOwner), [
          otherOwner,
        ]);
        expect(
          await fixture.avatarReferences(source.objectKey),
          [
            [_owner, null, entry.id],
          ],
          reason: 'Only the original entry must reference the key after undo.',
        );
        expect(
          await fixture.queuedKeys([source.objectKey]),
          isEmpty,
          reason: 'Undo must leave the still-referenced key out of the queue.',
        );
        await fixture.collectPreviouslyQueuedKey(source.objectKey);
        expect(await fixture.queuedKeys([source.objectKey]), isEmpty);
        expect(
          await getIt<PrivateAvatarRepositoryPort>().get(
            viewerId: _owner,
            objectKey: source.objectKey,
          ),
          jpeg,
        );
        expect(
          linkedAvatars,
          [_copyOnAccount(source)],
          reason: 'There must have been an account avatar for undo to remove.',
        );
      },
    );

    test(
      'undo keeps an avatar uploaded to the account after linking',
      () async {
        final entry = await fixture.entry();
        const account = PersonSubject.user(_account);
        final source = await fixture.upload(entry);
        final mergeId = await fixture.link(entry);
        final linkedAvatars = await fixture.avatars(account);

        final replacement = await fixture.upload(account, red: 40);
        expect(replacement.objectKey, isNot(source.objectKey));
        await fixture.undo(entry, mergeId);

        expect(await fixture.avatars(account), [replacement]);
        expect(await fixture.avatars(entry), [source]);
        expect(
          linkedAvatars,
          [_copyOnAccount(source)],
          reason:
              'The upload should have replaced the avatar copied by linking.',
        );
      },
    );

    test('undo succeeds after the owner removes the copied avatar', () async {
      final entry = await fixture.entry();
      const account = PersonSubject.user(_account);
      final source = await fixture.upload(entry);
      final mergeId = await fixture.link(entry);

      final deletedKeys = await fixture.deleteAccountAvatar();
      final keys = [source.objectKey];
      // Deleting the row can enqueue the key before unlink runs. Let GC
      // process any such job so this test can detect an enqueue by unlink.
      if ((await fixture.queuedKeys(keys)).isNotEmpty) {
        await fixture.collectQueuedKey(source.objectKey);
      }
      expect(await fixture.queuedKeys(keys), isEmpty);
      await fixture.undo(entry, mergeId);

      expect(await fixture.avatars(account), isEmpty);
      expect(await fixture.avatars(entry), [source]);
      expect(
        await fixture.queuedKeys(keys),
        isEmpty,
        reason: 'Undo must leave the source key out of the queue.',
      );
      expect(
        deletedKeys,
        [source.objectKey],
        reason: 'The owner should have removed the avatar copied by linking.',
      );
    });

    test('Field reports which active entries have an owner avatar', () async {
      final withImage = await fixture.entry();
      final withoutImage = await fixture.entry();
      await fixture.upload(withImage);

      expect(await fixture.fieldAvatarFlags(), {
        withImage.id: true,
        withoutImage.id: false,
      });
    });

    test('Field shows the private avatar again after undoing a link', () async {
      final entry = await fixture.entry();
      await fixture.upload(entry);

      final mergeId = await fixture.link(entry);
      expect(await fixture.fieldAvatarFlags(), isEmpty);
      await fixture.undo(entry, mergeId);

      expect(await fixture.fieldAvatarFlags(), {entry.id: true});
    });
  }, skip: skip);
}

extension on Map<String, Object?> {
  String get objectKey => this['object_key']! as String;
}

Map<String, Object?> _copyOnAccount(Map<String, Object?> source) => {
  'owner_id': source['owner_id'],
  'subject_user_id': _account,
  'subject_phantom_id': null,
  'object_key': source.objectKey,
  'blurhash': source['blurhash'],
  'width': source['width'],
  'height': source['height'],
  'created_at': isA<DateTime>(),
};

Uint8List _jpeg({int red = 180}) => image.encodeJpg(
  image.Image(width: 12, height: 8)..clear(image.ColorRgb8(red, 30, 60)),
);

final class _Fixture {
  const _Fixture(this.writer, this.handler);

  final Connection writer;
  final Handler handler;

  Future<Result> _sql(String statement, Map<String, Object?> parameters) =>
      writer.execute(Sql.named(statement), parameters: parameters);

  Future<void> reset() async {
    await writer.execute(
      'TRUNCATE public."user", public.attention_occurrence, '
      'public.private_object_gc, public.person_visible_set_cache CASCADE',
    );
    for (final (index, id) in [
      _owner,
      _otherOwner,
      _account,
      _otherAccount,
      _thirdAccount,
    ].indexed) {
      await _sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
        {'id': id, 'key': pgTestPublicKey('private-avatar-link', index + 1)},
      );
    }
    await _sql(
      '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@owner, @account, 1), (@owner, @otherAccount, 1),
       (@owner, @thirdAccount, 1)
''',
      {
        'owner': _owner,
        'account': _account,
        'otherAccount': _otherAccount,
        'thirdAccount': _thirdAccount,
      },
    );
  }

  Future<PersonSubject> entry() async => PersonSubject.phantom(
    await getIt<PhantomCase>().create(ownerId: _owner, name: 'An acquaintance'),
  );

  Future<Map<String, Object?>> upload(
    PersonSubject subject, {
    String owner = _owner,
    Uint8List? bytes,
    int red = 180,
  }) async {
    await getIt<PrivateAvatarRepositoryPort>().put(
      ownerId: owner,
      subject: subject,
      bytes: Stream.value(bytes ?? _jpeg(red: red)),
    );
    return (await avatars(subject, owner: owner)).single;
  }

  Future<List<Map<String, Object?>>> avatars(
    PersonSubject subject, {
    String owner = _owner,
  }) async {
    final rows = await _sql(
      '''
SELECT owner_id, subject_user_id, subject_phantom_id,
       object_key, blurhash, width, height, created_at
FROM public.person_private_avatar
WHERE owner_id = @owner
  AND subject_user_id IS NOT DISTINCT FROM @user::text
  AND subject_phantom_id IS NOT DISTINCT FROM @entry::text
''',
      {'owner': owner, 'user': subject.userId, 'entry': subject.phantomId},
    );
    return [for (final row in rows) row.toColumnMap()];
  }

  Future<String> link(PersonSubject entry, {String user = _account}) async {
    expect(
      await _post(
        r'mutation Link($phantomId: String!, $userId: String!) { '
        r'phantomLink(phantomId: $phantomId, userId: $userId) }',
        {'phantomId': entry.id, 'userId': user},
      ),
      {'phantomLink': true},
    );
    final rows = await _sql(
      '''
SELECT current_merge_id FROM public.phantom
WHERE id = @entry AND owner_id = @owner AND merged_user_id = @user
''',
      {'entry': entry.id, 'owner': _owner, 'user': user},
    );
    return rows.single.single! as String;
  }

  Future<void> undo(PersonSubject entry, String mergeId) async {
    expect(
      await _post(
        r'mutation UndoLink($phantomId: String!, $mergeId: String!) { '
        r'phantomUnmerge(phantomId: $phantomId, mergeId: $mergeId) }',
        {'phantomId': entry.id, 'mergeId': mergeId},
      ),
      {'phantomUnmerge': true},
    );
  }

  Future<Object?> avatarUndo(String mergeId, {required String user}) async {
    final rows = await _sql(
      '''
SELECT (undo -> 'avatar')::text FROM public.phantom_merge
WHERE id = @mergeId AND owner_id = @owner AND user_id = @user
''',
      {'mergeId': mergeId, 'owner': _owner, 'user': user},
    );
    final avatar = rows.single.single as String?;
    return avatar == null ? null : jsonDecode(avatar);
  }

  Future<Result> avatarReferences(String key) => _sql(
    '''
SELECT owner_id, subject_user_id, subject_phantom_id
FROM public.person_private_avatar WHERE object_key = @key
''',
    {'key': key},
  );

  Future<List<String>> queuedKeys(List<String> keys) async {
    final rows = await _sql(
      '''
SELECT object_key FROM public.private_object_gc
WHERE object_key = ANY(@keys::text[])
''',
      {'keys': keys},
    );
    return [for (final row in rows) row.single! as String];
  }

  Future<void> collectPreviouslyQueuedKey(String key) async {
    // Exercise collection of an eligible job after checking that undo itself
    // left no job behind. A delayed job must also respect the surviving row.
    await _sql(
      '''
INSERT INTO public.private_object_gc (object_key) VALUES (@key)
''',
      {'key': key},
    );
    await collectQueuedKey(key);
  }

  Future<void> collectQueuedKey(String key) async {
    const worker = 'private-avatar-test-worker';
    final gc = getIt<PrivateObjectGcPort>();
    final jobs = await gc.claim(leaseOwner: worker, now: DateTime.timestamp());
    expect(jobs.map((job) => job.objectKey), [key]);
    await gc.collect(objectKey: key, leaseOwner: worker);
  }

  Future<List<String>> deleteAccountAvatar() async {
    // There is no avatar-delete API. Model removal using the real scoped row
    // deletion, including its normal GC trigger.
    final rows = await writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
DELETE FROM public.person_private_avatar
WHERE owner_id = @owner AND subject_user_id = @user
RETURNING object_key
'''),
      parameters: {'owner': _owner, 'user': _account},
    );
    return [for (final row in rows) row.single! as String];
  }

  Future<Map<String, bool>> fieldAvatarFlags() async {
    // Take the normal Field path with a current visibility cache so the test
    // does not depend on the shared MeritRank service.
    await _sql(
      '''
INSERT INTO public.person_visible_set_cache
    (viewer_id, ctx, mr_epoch, trust_gen, peer_ids)
VALUES (
  @owner, @context,
  coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0),
  (SELECT generation FROM public.visibility_trust_generation WHERE id = true),
  ARRAY[]::text[])
ON CONFLICT (viewer_id, ctx) DO UPDATE
SET mr_epoch = EXCLUDED.mr_epoch,
    trust_gen = EXCLUDED.trust_gen,
    peer_ids = EXCLUDED.peer_ids
''',
      {'owner': _owner, 'context': kConstellationContext},
    );
    final data = await _post('''
query {
  constellationField(projection: FULL) {
    phantoms { id hasPrivateAvatar }
  }
}
''');
    final field = data['constellationField']! as Map<String, Object?>;
    final entries = (field['phantoms']! as List<Object?>)
        .cast<Map<String, Object?>>();
    return {
      for (final entry in entries)
        entry['id']! as String: entry['hasPrivateAvatar']! as bool,
    };
  }

  Future<Map<String, Object?>> _post(
    String query, [
    Map<String, Object?> variables = const {},
  ]) async {
    final token = getIt<AuthCase>().issueAccessToken(_owner).rawToken;
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://127.0.0.1:2080/api/v2/graphql'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    final payload = jsonDecode(body) as Map<String, Object?>;
    expect(payload['errors'], isNull, reason: body);
    return payload['data']! as Map<String, Object?>;
  }
}

final class _MemoryStorage implements RemoteStoragePort {
  final objects = <String, Uint8List>{};

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    final buffer = BytesBuilder(copy: false);
    await bytes.forEach(buffer.add);
    objects[path] = buffer.takeBytes();
    return path;
  }

  @override
  Future<Uint8List> getObject(String path) async =>
      objects[path] ?? (throw StateError('Missing stored object: $path'));

  @override
  Future<void> removeObject(String path) async {
    objects.remove(path);
  }
}
