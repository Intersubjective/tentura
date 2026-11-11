@Tags(['pg', 'repo-files'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';
import '../../support/post_publish_pg_support.dart';

final _author = postPublishAuthor(0);
const _post = 'Bpubrecover00';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_RECOVERY_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_recovery',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Post publication recovery requires reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('Post publication recovery', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb publisherDb;
    late TenturaDb editorDb;
    late Env env;
    late PostCase posts;
    late PostCase editor;
    late _Storage storage;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final base = target.databaseEnv;
      env = Env(
        environment: Environment.test,
        pgHost: base.pgHost,
        pgPort: base.pgPort,
        pgDatabase: base.pgDatabase,
        pgUsername: base.pgUsername,
        pgPassword: base.pgPassword,
        maxConnectionCount: 1,
        pgStatementTimeoutMs: 30000,
        printEnv: false,
        isDebugModeOn: false,
      );
      publisherDb = TenturaDb(env);
      editorDb = TenturaDb(env);
    });

    setUp(() async {
      await seedPostPublishFixture(writer);
      storage = _Storage();
      posts = PostPublishHarness.build(
        publisherDb,
        env,
        storage: storage,
      ).posts;
      editor = PostPublishHarness.build(editorDb, env, storage: storage).posts;
      await writer.execute(
        Sql.named('''
          INSERT INTO public.beacon
            (id, user_id, title, description, status, kind, forward_policy,
             is_discoverable)
          VALUES (@id, @author, '', '', 3, 1, 1, false)
        '''),
        parameters: {'id': _post, 'author': _author},
      );
      await posts.updatePostDraft(
        authorId: _author,
        beaconId: _post,
        body: 'Draft text',
        forwardPolicy: BeaconForwardPolicyValue.closed,
        lifetimeHours: 6,
      );
    });

    tearDown(() async {
      for (final table in ['beacon_participant', 'beacon_room_message']) {
        await writer.execute(
          'DROP TRIGGER IF EXISTS refuse_post_publish ON public.$table',
        );
      }
      await writer.execute(
        'DROP FUNCTION IF EXISTS public.refuse_post_publish()',
      );
    });

    tearDownAll(() async {
      await editorDb.close();
      await publisherDb.close();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<List<Object?>> draftState(String post) async =>
        (await writer.execute(
          Sql.named('''
            SELECT status, post_root_message_id, description, post_lifetime_hours,
              (SELECT count(*) FROM public.beacon_room_message m
               WHERE m.beacon_id = b.id)
            FROM public.beacon b WHERE b.id = @id
          '''),
          parameters: {'id': post},
        )).single.toList();

    Future<void> failPublication({required bool recipientFailure}) async {
      final table = recipientFailure
          ? 'beacon_participant'
          : 'beacon_room_message';
      final predicate = recipientFailure
          ? "NEW.beacon_id = '$_post' AND "
                "NEW.user_id = '$postPublishRecipient' AND NEW.role = 6"
          : "NEW.beacon_id = '$_post'";
      await writer.execute('''
        CREATE FUNCTION public.refuse_post_publish() RETURNS trigger
        LANGUAGE plpgsql AS \$\$
        BEGIN
          IF $predicate THEN
            RAISE EXCEPTION 'injected Post publication failure'
              USING ERRCODE = '23514';
          END IF;
          RETURN NEW;
        END
        \$\$
      ''');
      await writer.execute('''
        CREATE TRIGGER refuse_post_publish AFTER INSERT ON public.$table
        FOR EACH ROW EXECUTE FUNCTION public.refuse_post_publish()
      ''');
      await expectLater(
        _publish(
          posts,
          _post,
          body: 'Draft text',
          recipients: recipientFailure ? [postPublishRecipient] : [],
        ),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'SQLSTATE', '23514')
              .having(
                (e) => e.message,
                'injected failure',
                contains('injected Post publication failure'),
              ),
        ),
      );
      final state = await draftState(_post);
      expect(state[1], isNull, reason: 'failed publication has no root');
      expect(state[4], 0, reason: 'failed publication commits no room message');
    }

    Future<void> allowPublication() async {
      for (final table in ['beacon_participant', 'beacon_room_message']) {
        await writer.execute(
          'DROP TRIGGER IF EXISTS refuse_post_publish ON public.$table',
        );
      }
      await writer.execute('DROP FUNCTION public.refuse_post_publish()');
    }

    Future<void> expectRoot(
      String post,
      PostPublishResult result, {
      required String body,
    }) async {
      expect(result.beaconId, post);
      expect(result.rootMessageId, isNotEmpty);
      final rows = await writer.execute(
        Sql.named('''
          SELECT b.status, b.post_root_message_id, b.description,
                 b.post_lifetime_hours, m.author_id, m.body
          FROM public.beacon b
          JOIN public.beacon_room_message m ON m.id = b.post_root_message_id
          WHERE b.id = @id
        '''),
        parameters: {'id': post},
      );
      expect(rows.single.toList(), [
        BeaconStatus.open.smallintValue,
        result.rootMessageId,
        '',
        null,
        _author,
        body,
      ]);
    }

    test('failed recipient delivery preserves the saved draft text', () async {
      await failPublication(recipientFailure: true);
      expect(
        (await draftState(_post))[2],
        'Draft text',
        reason: 'the composer text survives until a root message commits',
      );
    });

    for (final recipientFailure in [true, false]) {
      test(
        recipientFailure
            ? 'the author can edit and retry after recipient delivery fails'
            : 'the author can edit and retry after root message creation fails',
        () async {
          await failPublication(recipientFailure: recipientFailure);
          // A second client edits the actual durable state left by publish.
          final saved = await editor.updatePostDraft(
            authorId: _author,
            beaconId: _post,
            body: 'Edited text',
            forwardPolicy: BeaconForwardPolicyValue.closed,
          );
          expect(saved, _post);
          expect((await draftState(_post))[2], 'Edited text');
          await allowPublication();
          final result = await _publish(
            posts,
            _post,
            body: 'Edited text',
            recipients: recipientFailure ? [postPublishRecipient] : [],
          );
          await expectRoot(_post, result, body: 'Edited text');
          if (recipientFailure) {
            final recipients = await writer.execute(
              Sql.named('''
                SELECT user_id FROM public.beacon_participant
                WHERE beacon_id = @id AND user_id = @recipient
              '''),
              parameters: {'id': _post, 'recipient': postPublishRecipient},
            );
            expect(recipients.single.single, postPublishRecipient);
          }
          await expectLater(
            editor.updatePostDraft(
              authorId: _author,
              beaconId: _post,
              body: 'Late edit',
              forwardPolicy: BeaconForwardPolicyValue.closed,
            ),
            throwsA(
              isA<BeaconCreateException>().having(
                (e) => e.description,
                'description',
                'Post is not an editable draft',
              ),
            ),
          );
          await expectRoot(_post, result, body: 'Edited text');
        },
      );
    }

    test('racing attachment removal either publishes the attachment or keeps '
        'an editable draft that can be refilled and published', () async {
      final runs =
          <
            ({
              String post,
              List<Object?> original,
              List<Object?> state,
              _Outcome<PostPublishResult> published,
              _Outcome<void> removed,
            })
          >[];
      var removalFirstCount = 0;
      var publicationFirstCount = 0;

      Future<void> expectPausedActorBeforePostLock(int pid, String post) async {
        final locks = await writer.execute(
          Sql.named('''
            SELECT l.granted FROM pg_locks l
            WHERE l.locktype = 'advisory' AND l.objsubid = 1
              AND ((l.classid::bigint << 32) | l.objid::bigint) =
                  hashtextextended(@post, 4242)
              AND l.pid = @pid AND l.database = (
                SELECT oid FROM pg_database WHERE datname = current_database())
          '''),
          parameters: {'post': post, 'pid': pid},
        );
        expect(
          locks,
          isEmpty,
          reason:
              'the paused actor must neither hold nor request the '
              'Post lock before the competing operation commits',
        );
      }

      for (var i = 0; i < 20; i++) {
        final post = 'Brecover${i.toString().padLeft(5, '0')}';
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon
              (id, user_id, title, description, status, kind, forward_policy,
               is_discoverable)
            VALUES (@id, @author, '', '', 3, 1, 1, false)
          '''),
          parameters: {'id': post, 'author': _author},
        );
        final attachment = await _addAttachment(posts, post, 'original.txt');
        final original = (await writer.execute(
          Sql.named('''
            SELECT file_url, file_name, mime, size_bytes
            FROM public.post_draft_attachment WHERE beacon_id = @id
          '''),
          parameters: {'id': post},
        )).single.toList();

        final reachedLock = Completer<int>();
        final releaseLock = Completer<void>();
        // Alternate both acquisition orderings. The paused operation is
        // already inside its transaction before its competitor starts, and
        // cannot acquire the real Post lock until that competitor commits.
        final forceRemoval = i.isEven;
        final pausedDb = forceRemoval ? publisherDb : editorDb;
        final pausedActor = PostPublishHarness.build(
          pausedDb,
          env,
          storage: storage,
          publishLock: _BeforeFirstMutationLock(
            PostLockRepository(pausedDb),
            () async {
              final backend = await pausedDb
                  .customSelect('SELECT pg_backend_pid() AS pid')
                  .getSingle();
              reachedLock.complete(backend.read<int>('pid'));
              await releaseLock.future.timeout(kStableStateWait);
            },
          ),
        ).posts;
        Future<_Outcome<void>> remove(PostCase actor) => _settle(
          actor.removeDraftAttachment(
            authorId: _author,
            beaconId: post,
            attachmentId: attachment,
          ),
        );
        Future<_Outcome<PostPublishResult>>? publishing;
        Future<_Outcome<void>>? removing;
        if (forceRemoval) {
          publishing = _settle(_publish(pausedActor, post, body: ''));
        } else {
          removing = remove(pausedActor);
        }
        late _Outcome<void> removed;
        late _Outcome<PostPublishResult> published;
        try {
          final pausedPid = await reachedLock.future.timeout(kStableStateWait);
          await expectPausedActorBeforePostLock(pausedPid, post);
          if (forceRemoval) {
            removing = remove(editor);
            removed = await removing.timeout(kCompletionWait);
            expect(
              removed.error,
              isNull,
              reason: 'removal must commit before releasing the publisher',
            );
            final count = await writer.execute(
              Sql.named(
                'SELECT count(*) FROM public.post_draft_attachment '
                'WHERE beacon_id = @id',
              ),
              parameters: {'id': post},
            );
            expect(count.single.single, 0);
            expect(await draftState(post), [
              BeaconStatus.draft.smallintValue,
              null,
              '',
              null,
              0,
            ]);
            removalFirstCount++;
          } else {
            publishing = _settle(_publish(posts, post, body: ''));
            published = await publishing.timeout(kCompletionWait);
            expect(
              published.error,
              isNull,
              reason: 'publication must commit before releasing the remover',
            );
            await expectRoot(post, published.value!, body: '');
            publicationFirstCount++;
          }
          // Independent database observations prove the competing commit
          // happened while the other operation was still before its Post lock.
          await expectPausedActorBeforePostLock(pausedPid, post);
        } finally {
          if (!releaseLock.isCompleted) releaseLock.complete();
          if (publishing != null) {
            published = await publishing.timeout(kCompletionWait);
          }
          if (removing != null) {
            removed = await removing.timeout(kCompletionWait);
          }
        }
        runs.add((
          post: post,
          original: original,
          state: await draftState(post),
          published: published,
          removed: removed,
        ));
      }

      expect(removalFirstCount, 10);
      expect(publicationFirstCount, 10);
      // Exercise every fresh draft and both orderings before judging outcomes:
      // an early missing-behaviour assertion must not skip the race coverage.
      for (final run in runs) {
        final (:post, :original, :state, :published, :removed) = run;
        if (published.error == null) {
          expect(
            removed.error,
            isA<BeaconCreateException>(),
            reason: 'removal must be refused once publication wins',
          );
          await expectRoot(post, published.value!, body: '');
          final attached = await writer.execute(
            Sql.named('''
              SELECT file_url, file_name, mime, size_bytes
              FROM public.beacon_room_message_attachment WHERE message_id = @id
            '''),
            parameters: {'id': published.value!.rootMessageId},
          );
          expect(attached.single.toList(), original);
          expect(
            storage.objects[original[0]],
            isNotNull,
            reason: 'the published attachment remains available',
          );
        } else {
          expect(
            removed.error,
            isNull,
            reason: 'only a committed removal may make publication empty',
          );
          expect(
            published.error,
            isA<BeaconCreateException>().having(
              (e) => e.description,
              'description',
              'A Post needs text or an attachment',
            ),
            reason: '$post: removal won, so Send must refuse an empty Post',
          );
          expect(
            state,
            [BeaconStatus.draft.smallintValue, null, '', null, 0],
            reason:
                '$post: an empty Post must remain an editable draft '
                'without a root or room message',
          );
          // Every refused, still-draft publication is recoverable through the
          // same upload and Send operations, with no direct SQL repair.
          await _addAttachment(editor, post, 'replacement.txt');
          final replacement = (await writer.execute(
            Sql.named(
              'SELECT file_url FROM public.post_draft_attachment '
              'WHERE beacon_id = @id',
            ),
            parameters: {'id': post},
          )).single.single;
          final retried = await _publish(posts, post, body: '');
          await expectRoot(post, retried, body: '');
          final attached = await writer.execute(
            Sql.named(
              'SELECT file_url, file_name FROM '
              'public.beacon_room_message_attachment WHERE message_id = @id',
            ),
            parameters: {'id': retried.rootMessageId},
          );
          expect(attached.single.toList(), [replacement, 'replacement.txt']);
        }
      }
    });
  });
}

Future<PostPublishResult> _publish(
  PostCase posts,
  String post, {
  required String body,
  List<String> recipients = const [],
}) => posts
    .publish(
      authorId: _author,
      beaconId: post,
      body: body,
      mentionUserIds: const [],
      mentionOffsets: const [],
      mentionLengths: const [],
      recipientIds: recipients,
      notes: const {},
    )
    .timeout(kCompletionWait);

Future<String> _addAttachment(PostCase posts, String post, String filename) =>
    posts
        .addDraftAttachment(
          authorId: _author,
          beaconId: post,
          bytes: Stream.value(Uint8List.fromList([65, 66, 67])),
          filename: filename,
          mimeType: 'text/plain',
        )
        .timeout(kCompletionWait);

typedef _Outcome<T> = ({T? value, Object? error});

Future<_Outcome<T>> _settle<T>(Future<T> work) async {
  try {
    return (value: await work, error: null);
  } on Object catch (error) {
    return (value: null, error: error);
  }
}

final class _BeforeFirstMutationLock implements PostLockPort {
  _BeforeFirstMutationLock(this.inner, this.before);

  final PostLockPort inner;
  final Future<void> Function() before;
  bool paused = false;

  @override
  Future<void> lockForPostMutation(String beaconId) async {
    if (!paused) {
      paused = true;
      await before();
    }
    // No production lock acquisition may precede the scheduling barrier.
    await inner.lockForPostMutation(beaconId);
  }

  @override
  Future<void> lockForPostDelivery(
    String beaconId, {
    required String senderId,
  }) => inner.lockForPostDelivery(beaconId, senderId: senderId);
}

final class _Storage extends Fake implements RemoteStoragePort {
  final objects = <String, Uint8List>{};

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    final builder = BytesBuilder();
    await bytes.forEach(builder.add);
    objects[path] = builder.takeBytes();
    return path;
  }

  @override
  Future<void> removeObject(String path) async {
    objects.remove(path);
  }
}
