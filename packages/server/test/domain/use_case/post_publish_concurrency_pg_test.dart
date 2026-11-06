@Tags(['pg', 'repo-files'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';

import 'package:graphql_server2/graphql_server2.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_post.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/field_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/person_field_items_page.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/hasura_pg_jwt_keys.dart';
import '../../support/isolated_hasura_session.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/post_publish_pg_support.dart';

const _pauseKey = "hashtextextended('test.post_publish.fanout_pause', 0)";
const _hierarchyKey = "hashtextextended('tentura.beacon_hierarchy.v1', 0)";

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_CONCURRENCY_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_concurrency',
  );
  final unavailable = await pgSkipReason(target);
  final dockerReachable = await IsolatedHasuraSession.isDockerAvailable();
  final skipHasura =
      dockerReachable ? false : 'Docker not available for isolated Hasura';
  if (unavailable != null) {
    test('Post publication concurrency requires reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('Post publication delivery and recovery', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Env env;
    late List<TenturaDb> actors;
    late List<PostPublishHarness> harnesses;
    IsolatedHasuraSession? hasura;
    late AuthCase auth;

    Future<void> expectPendingReaders(String post) async {
      if (hasura == null) {
        final keys = loadJwtKeysForHasuraPgTests();
        hasura = await IsolatedHasuraSession.start(
          databaseEnv: target.databaseEnv,
          jwtPublicPem: keys.publicKey,
        );
        await hasura!.applyRepoMetadata();
        await hasura!.assertMetadataConsistent();
        auth = AuthCase(
          _UnusedUsers(),
          _UnusedInvitations(),
          env: Env(
            environment: Environment.test,
            publicKey: keys.publicKey,
            privateKey: keys.privateKey,
            printEnv: false,
          ),
          logger: Logger('PendingPostReadersPgTest'),
        );
      }
      await _expectPendingReaders(
        actors[1],
        harnesses[1],
        post,
        hasura!,
        auth,
      );
    }

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
        pgStatementTimeoutMs: 60000,
        printEnv: false,
        isDebugModeOn: false,
      );
      // Six publishers and one budder, each with its own one-connection pool.
      actors = [for (var i = 0; i < 7; i++) TenturaDb(env)];
      harnesses = [for (final db in actors) PostPublishHarness.build(db, env)];
    });

    setUp(() async {
      await _seedIndependentPublishFixture(writer);
      for (final db in actors) {
        await db.customStatement("SET lock_timeout = '1s'");
      }
    });

    tearDownAll(() async {
      await hasura?.stop();
      for (final db in actors.reversed) {
        await db.close();
      }
      await tearDownDisposablePgWriter(session: session);
    });

    for (final checkOtherPosts in [true, false]) {
      test(
        checkOtherPosts
            ? 'slow recipient admission releases the hierarchy so other Posts can publish and bud without deadlocks'
            : 'budding during Post delivery waits for release or reports busy without a hierarchy lock cycle',
        () async {
          final pausedPost = _postId('race', 0);
          final author = postPublishAuthor(0);
          final otherPost = await _publish(harnesses[0], batch: 'warm');
          await _expectPublishedPost(writer, 'warm', 0, otherPost);
          final pid =
              (await actors[0]
                      .customSelect('SELECT pg_backend_pid() AS pid')
                      .getSingle())
                  .read<int>('pid');
          final budPid =
              (await actors[6]
                      .customSelect('SELECT pg_backend_pid() AS pid')
                      .getSingle())
                  .read<int>('pid');
          // The pause itself must outlive the contenders' one-second lock budget.
          await actors[0].customStatement("SET lock_timeout = '0'");
          await writer.execute('''
CREATE FUNCTION public.pause_post_recipient_insert() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  IF NEW.beacon_id = '$pausedPost'
     AND NEW.user_id = '$postPublishRecipient' AND NEW.role = 6 THEN
    PERFORM pg_advisory_xact_lock($_pauseKey);
  END IF;
  RETURN NEW;
END
\$\$
''');
          await writer.execute('''
CREATE TRIGGER pause_post_recipient_insert
AFTER INSERT ON public.beacon_participant
FOR EACH ROW EXECUTE FUNCTION public.pause_post_recipient_insert()
''');
          await writer.execute('SELECT pg_advisory_lock($_pauseKey)');
          final publishing = _settle(_publish(harnesses[0]));
          late List<({bool granted, String mode})> postLocks;
          late List<({bool granted, String mode})> senderLocks;
          late List<({bool granted, String mode})> hierarchyLocks;
          late List<Object?> visibleState;
          late _Outcome<PostBudResult> sameBud;
          Future<_Outcome<PostBudResult>>? budding;
          var pauseReleased = false;
          var budSucceededBeforeRelease = false;
          late _Outcome<PostPublishResult> published;
          try {
            await _waitForPause(writer, pid);
            postLocks = await _locks(
              writer,
              pid,
              "hashtextextended('$pausedPost', 4242)",
            );
            senderLocks = await _locks(
              writer,
              pid,
              "hashtextextended('tentura.user_block.v1:$author', 0)",
            );
            hierarchyLocks = await _locks(writer, pid, _hierarchyKey);
            visibleState = await _deliveryState(writer, pausedPost);

            if (checkOtherPosts) {
              final others = await Future.wait([
                for (var i = 1; i <= 5; i++)
                  _settle(
                    _publish(
                      harnesses[i],
                      author: i,
                      recipients: [_independentRecipient(i)],
                    ),
                  ),
              ]).timeout(kCompletionWait);
              for (var i = 1; i <= 5; i++) {
                expect(
                  others[i - 1].error,
                  isNull,
                  reason:
                      'author $i must finish publishing before pause release',
                );
                await _expectIndependentPublishedPost(
                  writer,
                  i,
                  others[i - 1].value!,
                );
              }
              expect(
                await _locks(writer, pid, _pauseKey),
                contains((granted: false, mode: 'ExclusiveLock')),
                reason:
                    'all five publishes committed while fan-out was still paused',
              );
              final otherBud = await _settle(
                _bud(harnesses[6], otherPost.beaconId, 'other'),
              ).timeout(kCompletionWait);
              expect(
                otherBud.error,
                isNull,
                reason:
                    'a bud on another Post must finish before pause release',
              );
              await expectBuddedChild(
                writer,
                otherBud.value!,
                otherPost.beaconId,
              );
            }
            // Release while the bud is waiting, so any later P -> H request in
            // delivery can form the real cycle instead of hiding behind a timeout.
            budding = _settle(_bud(harnesses[6], pausedPost, 'same')).then((
              outcome,
            ) {
              if (!pauseReleased && outcome.error == null) {
                budSucceededBeforeRelease = true;
              }
              return outcome;
            });
            await _waitForBudContention(writer, budPid, pausedPost, budding);
            expect(
              budSucceededBeforeRelease,
              isFalse,
              reason:
                  'a successful bud must remain pending until fan-out is released',
            );
          } finally {
            pauseReleased = true;
            await writer.execute('SELECT pg_advisory_unlock($_pauseKey)');
            published = await publishing.timeout(kCompletionWait);
            if (budding != null) {
              sameBud = await budding.timeout(kCompletionWait);
            }
            await writer.execute(
              'DROP TRIGGER pause_post_recipient_insert ON public.beacon_participant',
            );
            await writer.execute(
              'DROP FUNCTION public.pause_post_recipient_insert()',
            );
          }

          expect(
            budSucceededBeforeRelease,
            isFalse,
            reason:
                'a successful bud must complete after the pause is released',
          );
          expect(
            sameBud.error,
            isNot(
              isA<ServerException>().having((e) => e.code, 'SQLSTATE', '40P01'),
            ),
            reason: 'the forced same-Post lock contention must never deadlock',
          );
          // Verify committed results before judging the lock snapshot. A no-op
          // publish cannot pass merely by holding fewer locks.
          expect(published.error, isNull);
          await _expectPublishedPost(writer, 'race', 0, published.value!);
          final admission = await writer.execute(
            Sql.named(
              'SELECT role, room_access FROM public.beacon_participant '
              'WHERE beacon_id = @post AND user_id = @recipient',
            ),
            parameters: {'post': pausedPost, 'recipient': postPublishRecipient},
          );
          expect(admission.single.toList(), [6, 3]);
          expect(postLocks, contains((granted: true, mode: 'ExclusiveLock')));
          expect(senderLocks, contains((granted: true, mode: 'ShareLock')));
          expect(
            hierarchyLocks,
            isEmpty,
            reason: 'fan-out must neither hold nor wait for the hierarchy lock',
          );
          expect(
            visibleState,
            [0, null, 0, 0, 0],
            reason:
                'status commits before delivery; uncommitted edges stay hidden',
          );
          if (sameBud.error case final error?) {
            expect(
              error,
              isA<ServerException>().having(
                (e) => e.code,
                'SQLSTATE (busy, never deadlock)',
                '55P03',
              ),
            );
            // A busy attempt must be retryable after delivery commits.
            await expectBuddedChild(
              writer,
              await _bud(harnesses[6], pausedPost, 'same'),
              pausedPost,
            );
          } else {
            await expectBuddedChild(writer, sameBud.value!, pausedPost);
          }
        },
      );
    }

    test('a block committed before delivery preserves an author-only pending '
        'Post that can be retried with different recipients', () async {
      final post = _postId('race', 0);
      final author = postPublishAuthor(0);
      var crossedDeliveryBoundary = false;
      final lock = _BeforeDeliveryLock(PostLockRepository(actors[0]), () async {
        crossedDeliveryBoundary = true;
        // Runs on an independent connection, before U/P are acquired. If tx1
        // still held H this real block INSERT could not commit here.
        await writer.execute("SET lock_timeout = '1s'");
        await writer.execute(
          Sql.named(
            'INSERT INTO public.user_block '
            '(blocker_id, blocked_id, origin_id) '
            'VALUES (@recipient, @author, @author)',
          ),
          parameters: {'recipient': postPublishRecipient, 'author': author},
        );
      });
      final publisher = PostPublishHarness.build(
        actors[0],
        env,
        publishLock: lock,
      );
      final failed = await _settle(_publish(publisher));
      expect(
        failed.error,
        isA<UnauthorizedException>(),
        reason: 'delivery must re-check the block after the status commit',
      );
      expect(crossedDeliveryBoundary, isTrue);
      expect(await _deliveryState(writer, post), [0, null, 0, 0, 0]);
      await expectPendingReaders(post);

      await _makePeers(writer, author, postPublishAuthor(1));
      final recovered = await _publish(
        harnesses[0],
        recipients: [postPublishAuthor(1)],
        body: 'Retry delivery',
        notes: {postPublishAuthor(1): 'Use the retry audience'},
      );
      expect(recovered.beaconId, post);
      expect(recovered.rootMessageId, isNotEmpty);
      await _expectRetryDelivery(
        writer,
        post,
        recovered.rootMessageId,
        postPublishAuthor(1),
        'Retry delivery',
        'Use the retry audience',
      );
    }, skip: skipHasura);

    test(
      'an author resumes an open Post without a root using the retry body, '
      'audience and notes, and successful retries keep the same message',
      () async {
        final post = _postId('race', 0);
        final author = postPublishAuthor(0);
        final recipient = postPublishAuthor(1);
        await _makePeers(writer, author, recipient);
        // The same real status operation used by tx1 produces the durable
        // pending state, without inventing a domain entity or a parallel pipeline.
        await harnesses[0].beacons.publishDraft(userId: author, beaconId: post);
        expect(await _deliveryState(writer, post), [0, null, 0, 0, 0]);
        await expectPendingReaders(post);
        final before = (await writer.execute(
          Sql.named(
            'SELECT published_at, expires_at, forward_policy '
            'FROM public.beacon WHERE id = @post',
          ),
          parameters: {'post': post},
        )).single.toList();
        final body = 'Hello @$recipient';
        final result = await _publish(
          harnesses[0],
          recipients: [recipient],
          body: body,
          notes: {recipient: 'A new audience'},
          mentions: [recipient],
          // Delivery retries must skip tx1 rather than restamp the lifetime or
          // change the policy from the original status transaction.
          lifetimeHours: 1,
          policy: BeaconForwardPolicyValue.closed,
        );
        expect(result.beaconId, post);
        expect(result.rootMessageId, isNotEmpty);
        await _expectRetryDelivery(
          writer,
          post,
          result.rootMessageId,
          recipient,
          body,
          'A new audience',
        );
        final mentions = await writer.execute(
          Sql.named(
            'SELECT mentions FROM public.beacon_room_message WHERE id = @id',
          ),
          parameters: {'id': result.rootMessageId},
        );
        expect(
          mentions.single.single,
          [recipient],
          reason:
              'the retry audience must be admitted before mention resolution',
        );
        final again = await _publish(
          harnesses[0],
          recipients: [postPublishRecipient],
          body: 'This must not become a second message',
        );
        expect(again.beaconId, result.beaconId);
        expect(again.rootMessageId, result.rootMessageId);
        await _expectRetryDelivery(
          writer,
          post,
          result.rootMessageId,
          recipient,
          body,
          'A new audience',
        );
        final after = (await writer.execute(
          Sql.named(
            'SELECT published_at, expires_at, forward_policy '
            'FROM public.beacon WHERE id = @post',
          ),
          parameters: {'post': post},
        )).single.toList();
        expect(after, before);
      },
      skip: skipHasura,
    );

    test('failed recipient admission rolls back delivery while the published '
        'status and chosen lifetime remain committed', () async {
      final post = _postId('race', 0);
      await writer.execute('''
CREATE FUNCTION public.refuse_post_recipient_insert() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  IF NEW.beacon_id = '$post'
     AND NEW.user_id = '$postPublishRecipient' AND NEW.role = 6 THEN
    RAISE EXCEPTION 'test recipient admission failure' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
\$\$
''');
      await writer.execute('''
CREATE TRIGGER refuse_post_recipient_insert
AFTER INSERT ON public.beacon_participant
FOR EACH ROW EXECUTE FUNCTION public.refuse_post_recipient_insert()
''');
      late _Outcome<PostPublishResult> failed;
      try {
        failed = await _settle(_publish(harnesses[0], lifetimeHours: 6));
      } finally {
        await writer.execute(
          'DROP TRIGGER refuse_post_recipient_insert ON public.beacon_participant',
        );
        await writer.execute(
          'DROP FUNCTION public.refuse_post_recipient_insert()',
        );
      }
      expect(
        failed.error,
        isA<ServerException>()
            .having((e) => e.code, 'SQLSTATE', '23514')
            .having(
              (e) => e.message,
              'injected admission failure',
              contains('test recipient admission failure'),
            ),
      );
      expect(
        await _deliveryState(writer, post),
        [
          0,
          null,
          0,
          0,
          0,
        ],
        reason: 'delivery failure must not roll the status back to draft',
      );
      final lifetime = await writer.execute(
        Sql.named(
          "SELECT expires_at - published_at = interval '6 hours' "
          'FROM public.beacon WHERE id = @post',
        ),
        parameters: {'post': post},
      );
      expect(lifetime.single.single, isTrue);
      final receipts = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.notification_outbox '
          'WHERE beacon_id = @post',
        ),
        parameters: {'post': post},
      );
      expect(
        receipts.single.single,
        0,
        reason: 'failed delivery must not commit recipient notifications',
      );
      await expectPendingReaders(post);
    }, skip: skipHasura);
  });
}

String _independentRecipient(int i) => 'Upubpeer00$i';
String _postId(String batch, int author) =>
    postPublishId(batch, author).padRight(13, '0');

/// Extend the existing fixture locally; its shared seeder keeps its original
/// five-author audience and remains unchanged for existing regression tests.
Future<void> _seedIndependentPublishFixture(Connection writer) async {
  await seedPostPublishFixture(writer);
  await writer.execute('TRUNCATE public.beacon CASCADE');
  await writer.execute(
    Sql.named(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @id, @key)',
    ),
    parameters: {
      'id': postPublishAuthor(5),
      'key': pgTestPublicKey('pubcon', 7),
    },
  );
  for (var i = 0; i < 6; i++) {
    for (final batch in ['warm', 'race']) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon '
          '(id, user_id, title, description, status, kind, forward_policy, is_discoverable) '
          "VALUES (@id, @author, '', '', 3, 1, 1, false)",
        ),
        parameters: {'id': _postId(batch, i), 'author': postPublishAuthor(i)},
      );
    }
  }
  for (var i = 1; i <= 5; i++) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {
        'id': _independentRecipient(i),
        'key': pgTestPublicKey('peerpub', i),
      },
    );
    await _makePeers(writer, postPublishAuthor(i), _independentRecipient(i));
  }
}

Future<void> _expectIndependentPublishedPost(
  Connection writer,
  int author,
  PostPublishResult result,
) => _expectPublishedPost(
  writer,
  'race',
  author,
  result,
  recipient: _independentRecipient(author),
);

Future<void> _expectPublishedPost(
  Connection writer,
  String batch,
  int author,
  PostPublishResult result, {
  String recipient = postPublishRecipient,
}) async {
  final post = _postId(batch, author);
  expect(result.beaconId, post);
  expect(result.rootMessageId, isNotEmpty);
  await _expectRetryDelivery(
    writer,
    post,
    result.rootMessageId,
    recipient,
    postPublishBody(author),
    '',
  );
  final rows = await writer.execute(
    Sql.named('''
SELECT m.author_id,
  (SELECT count(*) FROM public.notification_outbox n
   WHERE n.beacon_id = @post AND n.account_id = @recipient)
FROM public.beacon_room_message m WHERE m.id = @root
'''),
    parameters: {
      'post': post,
      'root': result.rootMessageId,
      'recipient': recipient,
    },
  );
  expect(rows.single.toList(), [postPublishAuthor(author), 1]);
}

Future<PostPublishResult> _publish(
  PostPublishHarness harness, {
  String batch = 'race',
  int author = 0,
  List<String> recipients = const [postPublishRecipient],
  String? body,
  Map<String, String> notes = const {},
  List<String> mentions = const [],
  int? lifetimeHours,
  BeaconForwardPolicyValue policy = BeaconForwardPolicyValue.open,
}) => harness.posts.publish(
  authorId: postPublishAuthor(author),
  beaconId: _postId(batch, author),
  body: body ?? postPublishBody(author),
  mentionUserIds: mentions,
  mentionOffsets: [for (final _ in mentions) 6],
  mentionLengths: [for (final id in mentions) id.length + 1],
  recipientIds: recipients,
  notes: notes,
  forwardPolicy: policy,
  lifetimeHours: lifetimeHours,
);

Future<PostBudResult> _bud(
  PostPublishHarness harness,
  String post,
  String command,
) => harness.buds.budFromPost(
  actorUserId: postPublishAuthor(0),
  postId: post,
  clientCommandId: 'bud-$command',
  title: 'Organise a meeting',
  description: 'Turn the discussion into a Request',
);

typedef _Outcome<T> = ({T? value, Object? error});

Future<_Outcome<T>> _settle<T>(Future<T> operation) async {
  try {
    return (value: await operation, error: null);
  } catch (error) {
    return (value: null, error: error);
  }
}

/// Every lock observation identifies the key, backend and current database.
Future<List<({bool granted, String mode})>> _locks(
  Connection writer,
  int pid,
  String key,
) async {
  final rows = await writer.execute('''
SELECT l.granted, l.mode FROM pg_locks l
WHERE l.locktype = 'advisory' AND l.objsubid = 1
  AND ((l.classid::bigint << 32) | l.objid::bigint) = $key
  AND l.pid = $pid AND l.database = (
    SELECT oid FROM pg_database WHERE datname = current_database())
''');
  return [
    for (final row in rows) (granted: row[0]! as bool, mode: row[1]! as String),
  ];
}

Future<void> _waitForPause(Connection writer, int pid) async {
  final deadline = DateTime.now().add(kStableStateWait);
  while (DateTime.now().isBefore(deadline)) {
    if ((await _locks(writer, pid, _pauseKey)).any((lock) => !lock.granted)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('publisher did not reach the AFTER INSERT recipient pause');
}

Future<void> _waitForBudContention(
  Connection writer,
  int pid,
  String post,
  Future<_Outcome<PostBudResult>> budding,
) async {
  _Outcome<PostBudResult>? completed;
  void expectPendingOrBusy() {
    if (completed case final outcome?) {
      expect(
        outcome.error,
        isA<ServerException>().having((e) => e.code, 'SQLSTATE', '55P03'),
        reason: 'before release the bud must remain pending or fail as busy',
      );
    }
  }

  unawaited(
    budding.then((outcome) {
      completed = outcome;
    }),
  );
  final deadline = DateTime.now().add(kStableStateWait);
  while (DateTime.now().isBefore(deadline)) {
    // H is included so the current implementation also reaches this gate;
    // delivery without H lets the contender take H and then wait on P.
    for (final key in [_hierarchyKey, "hashtextextended('$post', 4242)"]) {
      if ((await _locks(writer, pid, key)).any((lock) => !lock.granted)) {
        expectPendingOrBusy();
        return;
      }
    }
    if (completed != null) {
      expectPendingOrBusy();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('bud neither completed nor reached its conflicting Post/hierarchy lock');
}

/// status, root, edges, addressees and non-system messages visible after commit.
Future<List<Object?>> _deliveryState(Connection writer, String post) async =>
    (await writer.execute(
      Sql.named('''
SELECT status, post_root_message_id,
  (SELECT count(*) FROM public.beacon_forward_edge WHERE beacon_id = @post),
  (SELECT count(*) FROM public.beacon_participant
   WHERE beacon_id = @post AND role = 6),
  (SELECT count(*) FROM public.beacon_room_message
   WHERE beacon_id = @post AND system_message_kind IS NULL)
FROM public.beacon WHERE id = @post
'''),
      parameters: {'post': post},
    )).single.toList();

Future<void> _makePeers(Connection writer, String author, String recipient) =>
    writer.execute(
      Sql.named(
        'INSERT INTO public.vote_user (subject, object, amount) '
        'VALUES (@author, @recipient, 1), (@recipient, @author, 1)',
      ),
      parameters: {'author': author, 'recipient': recipient},
    );

Future<void> _expectPendingReaders(
  TenturaDb db,
  PostPublishHarness harness,
  String post,
  IsolatedHasuraSession hasura,
  AuthCase auth,
) async {
  final author = postPublishAuthor(0);
  final summary = await harness.posts.postSummary(
    viewerId: author,
    beaconId: post,
  );
  expect(summary, isNotNull);
  expect(summary!.rootExcerpt, isNull);
  expect(summary.rootImageUrl, isNull);
  expect(summary.unreadCount, 0);
  expect(summary.status, BeaconStatus.open);
  expect(
    (await harness.posts.myPosts(author)).map((p) => p.id),
    contains(post),
  );
  final access = BeaconAccessRepository(db);
  final field = FieldVisibilityRepository(db);
  final snapshotReader = ConstellationFieldRepository(
    db,
    DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
  );
  final query = QueryPost(postCase: harness.posts);
  final graphQL = GraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('Query', null)..fields.addAll(query.all),
    ),
  );
  for (final viewer in [author, postPublishRecipient, postPublishAuthor(2)]) {
    final own = viewer == author;
    final projection = await graphQL.parseAndExecute(
      '''
query {
  myPosts { id rootExcerpt rootImageUrl lastMessageExcerpt unreadCount isAuthor status }
  postSummary(id: "$post") {
    id rootExcerpt rootImageUrl lastMessageExcerpt unreadCount isAuthor status
  }
}
''',
      globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
    );
    final ownSummary = {
      'id': post,
      'rootExcerpt': null,
      'rootImageUrl': null,
      'lastMessageExcerpt': null,
      'unreadCount': 0,
      'isAuthor': true,
      'status': 0,
    };
    expect(
      projection,
      {
        'myPosts': own ? [ownSummary] : <Object>[],
        'postSummary': own ? ownSummary : null,
      },
      reason: 'GraphQL must serialize a pending Post only for its author',
    );
    final response = await http
        .post(
          Uri.parse('${hasura.baseUrl}/v1/graphql'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer ${auth.issueAccessToken(viewer).rawToken}',
          },
          body: jsonEncode({
            'query':
                '''
query {
  beacon_by_pk(id: "$post") { id status post_root_message_id can_read_content }
  beacon(where: {id: {_eq: "$post"}}) { id status post_root_message_id can_read_content }
}
''',
          }),
        )
        .timeout(kCompletionWait);
    expect(response.statusCode, 200);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload['errors'], isNull, reason: response.body);
    final ownRow = {
      'id': post,
      'status': 0,
      'post_root_message_id': null,
      'can_read_content': true,
    };
    expect(
      payload['data'],
      {
        'beacon_by_pk': own ? ownRow : null,
        'beacon': own ? [ownRow] : <Object>[],
      },
      reason:
          'real Hasura user permissions must hide pending Posts from nonauthors',
    );
    expect(await access.canReadContent(beaconId: post, viewerId: viewer), own);
    if (!own) {
      expect(
        await harness.posts.postSummary(viewerId: viewer, beaconId: post),
        isNull,
      );
      expect(
        (await harness.posts.myPosts(viewer)).map((p) => p.id),
        isNot(contains(post)),
      );
    }
    final page = await field.personItems(
      viewerId: viewer,
      personId: author,
      bucket: PersonFieldBucket.active,
      words: const [],
    );
    expect(
      page.items.map((item) => item.id),
      own ? contains(post) : isNot(contains(post)),
    );
    final search = await field.search(
      viewerId: viewer,
      context: '',
      words: const [],
    );
    expect(
      search.posts.map((item) => item.id),
      own ? contains(post) : isNot(contains(post)),
    );
    final snapshot = await snapshotReader.readSnapshot(
      viewerId: viewer,
      context: '',
      params: (
        filters: ConstellationFieldMembershipFilters.defaults,
        projection: ConstellationProjection.full,
      ),
    );
    expect(
      snapshot.posts.map((item) => item.id),
      own ? contains(post) : isNot(contains(post)),
    );
    if (own) {
      expect(snapshot.posts.single.rootExcerpt, '');
    }
    expect(
      await BeaconRoomRepository(
        db,
      ).postRootExcerpts([post], viewerUserId: viewer),
      isEmpty,
      reason: 'room root-excerpt projection must tolerate a missing root',
    );
  }
}

final class _UnusedUsers extends Fake implements UserRepositoryPort {}

final class _UnusedInvitations extends Fake
    implements InvitationRepositoryPort {}

Future<void> _expectRetryDelivery(
  Connection writer,
  String post,
  String root,
  String recipient,
  String body,
  String note,
) async {
  expect(await _deliveryState(writer, post), [0, root, 1, 1, 1]);
  final delivered = await writer.execute(
    Sql.named('''
SELECT e.recipient_id, e.note, bp.role, bp.room_access, m.body
FROM public.beacon_forward_edge e
JOIN public.beacon_participant bp
  ON bp.beacon_id = e.beacon_id AND bp.user_id = e.recipient_id
JOIN public.beacon b ON b.id = e.beacon_id
JOIN public.beacon_room_message m ON m.id = b.post_root_message_id
WHERE e.beacon_id = @post
'''),
    parameters: {'post': post},
  );
  expect(delivered.single.toList(), [recipient, note, 6, 3, body]);
}

/// Injects only a scheduling point; the real lock repository, block triggers,
/// fan-out, message creation and attention dispatch remain in use.
final class _BeforeDeliveryLock implements PostLockPort {
  _BeforeDeliveryLock(this.delegate, this.beforeDelivery);

  final PostLockPort delegate;
  final Future<void> Function() beforeDelivery;
  bool _called = false;

  @override
  Future<void> lockForPostMutation(String beaconId) =>
      delegate.lockForPostMutation(beaconId);

  @override
  Future<void> lockForPostDelivery(
    String beaconId, {
    required String senderId,
  }) async {
    if (!_called) {
      _called = true;
      await beforeDelivery();
    }
    await delegate.lockForPostDelivery(beaconId, senderId: senderId);
  }
}
