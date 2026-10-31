@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ustmtauthor001';
const _beacon = 'Bstmtpost0001';
const _stranger = 'Ustmtstrange1';
const _body = 'Hello everyone, welcome to the thread';
const _fewRecipients = 2;
const _manyRecipients = 12;
const _kindPost = 1;
const _statusOpen = 0;
const _statusDraft = 3;

String _recipient(int i) => 'Ustmtrecip${i.toString().padLeft(4, '0')}';

/// Publishing a Post to a group of people costs a bounded number of SQL
/// statements: the work done for the whole audience (edges, addressees,
/// receipts, attention snapshots, mention suppression) is set-based, so
/// adding people to the audience does not add statements. Sentry flags a
/// per-recipient query loop inside one transaction as an N+1.
///
/// Statements are counted at the Drift executor, so a query issued anywhere
/// below `PostCase.publish` (forwarding, attention intents, the root message)
/// is seen, and the rows each publish stores are checked so a "fix" that
/// simply stops doing the work does not pass.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_STATEMENT_COUNT_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_statement_count',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('PostCase.publish statement count', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late _StatementRecorder recorder;
    late _Harness harness;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      recorder = _StatementRecorder();
      database = TenturaDb.forTest(
        database: PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
          enableMigrations: false,
        ).interceptWith(recorder),
      );
      harness = _Harness.build(database, target.databaseEnv);
    });
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    /// Publishes a fresh draft Post to [recipientCount] people and returns the
    /// SQL statements the publish issued.
    Future<List<String>> publishTo(
      int recipientCount, {
      bool mentionEveryone = false,
    }) async {
      await _seed(writer, recipientCount: _manyRecipients);
      final recipients = [
        for (var i = 0; i < recipientCount; i++) _recipient(i),
      ];
      final mentioned = mentionEveryone ? recipients : const <String>[];
      recorder.reset();
      await harness.posts.publish(
        authorId: _author,
        beaconId: _beacon,
        body: _body,
        mentionUserIds: mentioned,
        mentionOffsets: [for (var i = 0; i < mentioned.length; i++) 0],
        mentionLengths: [for (var i = 0; i < mentioned.length; i++) 1],
        recipientIds: recipients,
        notes: {for (final id in recipients) id: 'Note for $id'},
        forwardPolicy: BeaconForwardPolicyValue.closed,
      );
      return recorder.statements;
    }

    test('the number of statements issued does not grow with the number of '
        'people the Post is published to', () async {
      final few = await publishTo(_fewRecipients);
      final many = await publishTo(_manyRecipients);

      expect(
        many.length,
        lessThanOrEqualTo(few.length),
        reason:
            'publishing to $_fewRecipients people took ${few.length} '
            'statements, publishing to $_manyRecipients took ${many.length}. '
            'Statements that ran more often with the larger audience:\n'
            '${_grewWith(few: few, many: many)}',
      );
    });

    test('mentioning everyone the Post is published to does not make the '
        'number of statements grow with the audience', () async {
      final few = await publishTo(_fewRecipients, mentionEveryone: true);
      final many = await publishTo(_manyRecipients, mentionEveryone: true);

      expect(
        many.length,
        lessThanOrEqualTo(few.length),
        reason:
            'mentioning $_fewRecipients people took ${few.length} '
            'statements, mentioning $_manyRecipients took ${many.length}. '
            'Statements that ran more often with the larger audience:\n'
            '${_grewWith(few: few, many: many)}',
      );
    });

    test('a Post published to many people is still delivered to every one of '
        'them', () async {
      await publishTo(_manyRecipients);

      final delivered = await _delivery(writer);
      expect(delivered.status, _statusOpen);
      expect(delivered.rootMessageStored, isTrue);
      expect(delivered.forwardEdges, _manyRecipients);
      expect(delivered.addressees, _manyRecipients);
      expect(
        delivered.attentionRecipients,
        _manyRecipients,
        reason: 'every person gets an attention snapshot',
      );
      expect(
        delivered.recipientsWithNote,
        _manyRecipients,
        reason: 'each person keeps their own note on the forward edge',
      );
    });
  });
}

/// The SQL texts that ran more often in [many] than in [few], with both
/// counts, so a failure names the per-recipient statement.
String _grewWith({required List<String> few, required List<String> many}) {
  Map<String, int> tally(List<String> statements) {
    final counts = <String, int>{};
    for (final sql in statements) {
      final key = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  final fewCounts = tally(few);
  final lines = <String>[];
  tally(many).forEach((sql, count) {
    final before = fewCounts[sql] ?? 0;
    if (count > before) {
      final shown = sql.length > 160 ? '${sql.substring(0, 160)}…' : sql;
      lines.add('  x$before -> x$count  $shown');
    }
  });
  return lines.isEmpty ? '  (none)' : lines.join('\n');
}

/// Records the SQL text of every statement Drift sends.
class _StatementRecorder extends QueryInterceptor {
  final _statements = <String>[];

  List<String> get statements => List.of(_statements);

  void reset() => _statements.clear();

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    _statements.addAll(statements.statements);
    return super.runBatched(executor, statements);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

Future<void> _seed(Connection writer, {required int recipientCount}) async {
  await writer.execute('''
    TRUNCATE TABLE public.notification_outbox,
      public.attention_occurrence_recipient, public.attention_occurrence,
      public.beacon, public."user" CASCADE
  ''');
  final people = [
    _author,
    _stranger,
    for (var i = 0; i < recipientCount; i++) _recipient(i),
  ];
  for (var i = 0; i < people.length; i++) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES (@id, @name, @key)
      '''),
      parameters: {
        'id': people[i],
        'name': 'Person $i',
        'key': pgTestPublicKey(
          's${String.fromCharCode(97 + i ~/ 9)}',
          i % 9 + 1,
        ),
      },
    );
  }
  for (var i = 0; i < recipientCount; i++) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public.vote_user (subject, object, amount)
        VALUES (@author, @peer, 1), (@peer, @author, 1)
      '''),
      parameters: {'author': _author, 'peer': _recipient(i)},
    );
  }
  await writer.execute(
    Sql.named('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, forward_policy,
         is_discoverable)
      VALUES (@beacon, @author, '', '', @draft, @kind, 1, false)
    '''),
    parameters: {
      'beacon': _beacon,
      'author': _author,
      'draft': _statusDraft,
      'kind': _kindPost,
    },
  );
}

typedef _Delivery = ({
  int status,
  bool rootMessageStored,
  int forwardEdges,
  int addressees,
  int attentionRecipients,
  int recipientsWithNote,
});

Future<_Delivery> _delivery(Connection writer) async {
  final row = (await writer.execute(
    Sql.named('''
      SELECT status, post_root_message_id IS NOT NULL,
        (SELECT count(*) FROM public.beacon_forward_edge WHERE beacon_id = @id),
        (SELECT count(*) FROM public.beacon_participant
         WHERE beacon_id = @id AND role = 6),
        (SELECT count(*) FROM public.attention_occurrence_recipient),
        (SELECT count(*) FROM public.beacon_forward_edge
         WHERE beacon_id = @id AND note LIKE 'Note for %')
      FROM public.beacon WHERE id = @id
    '''),
    parameters: {'id': _beacon},
  )).single;
  return (
    status: row[0]! as int,
    rootMessageStored: row[1]! as bool,
    forwardEdges: row[2]! as int,
    addressees: row[3]! as int,
    attentionRecipients: row[4]! as int,
    recipientsWithNote: row[5]! as int,
  );
}

final class _Harness {
  const _Harness(this.posts, this.room);

  final PostCase posts;
  final BeaconRoomCase room;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('PostCasePublishPgTest');
    final uow = MutatingUnitOfWork(db);
    final attention = TransactionalAttentionCase(
      uow,
      AttentionDispatchRepository(db, logger),
    );
    final beaconRepository = BeaconRepository(db);
    final roomRepository = BeaconRoomRepository(db);
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final blocks = UserBlockRepository(env, db);
    final hierarchy = BeaconHierarchyRepository(db);
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        roomRepository,
        db,
        help,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _UnusedGenealogy(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      blocks,
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      help,
      env: env,
      logger: logger,
    );
    final images = _UnusedImages();
    final tasks = _Tasks();
    final beacons = BeaconCase(
      beaconRepository,
      images,
      _UnusedImageGc(),
      tasks,
      commitmentQuery,
      access,
      hierarchy,
      FakeBeaconChildCreatePort(),
      BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(db),
        env: env,
        logger: logger,
      ),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final forwards = ForwardCase(
      ForwardEdgeRepository(db),
      ForwardAttributionRepository(db),
      help,
      InboxRepository(db),
      CapabilityEvidenceRepository(db),
      beaconRepository,
      blocks,
      PersonVisibilityRepository(db),
      access,
      attentionIntents: intents,
      attention: attention,
      postLock: PostLockRepository(db),
      env: env,
      logger: logger,
    );
    final room = BeaconRoomCase(
      roomRepository,
      CoordinationItemRepository(db),
      _UnusedFactCards(),
      images,
      tasks,
      _Storage(),
      _UnusedPolling(),
      _Quota(),
      blocks,
      uow,
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    return _Harness(
      PostCase(
        beaconCase: beacons,
        forwardCase: forwards,
        roomCase: room,
        beaconRepository: beaconRepository,
        postLock: PostLockRepository(db),
        attention: attention,
      ),
      room,
    );
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

final class _Storage extends Fake implements RemoteStoragePort {
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    return path;
  }
}

final class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}
