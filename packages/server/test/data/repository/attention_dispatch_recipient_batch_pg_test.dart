@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

/// Forwarding a Request to many people (`ForwardBeacon`) records one attention
/// occurrence with one recipient snapshot per person.
///
/// The recipient snapshots must be written by a bounded number of SQL
/// statements — the cost may not grow with the number of people forwarded to
/// (Sentry flags one INSERT per recipient inside a single transaction as an
/// N+1). The stored rows keep exactly the values the per-recipient path wrote:
/// reasons, role facts, collapse key and channel eligibility.
///
/// The cost is pinned at two levels: the attention repository on its own, and
/// the whole `ForwardCase.forward` write path, so a recipient INSERT issued
/// anywhere on the way to the table is counted.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_RECIPIENT_BATCH_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_attention_recipient_batch',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('attention dispatch recipient snapshots — disposable Postgres', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late _StatementRecorder recorder;
    late AttentionDispatchRepository dispatch;
    late MutatingUnitOfWork unitOfWork;
    late ForwardCase forwardCase;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
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
        dispatch = AttentionDispatchRepository(
          database,
          Logger('attention-dispatch-recipient-batch-test'),
        );
        unitOfWork = MutatingUnitOfWork(database);
        final env = target.databaseEnv;
        final logger = Logger('attention-dispatch-recipient-batch-test');
        final helpOffers = HelpOfferRepository(database);
        forwardCase = ForwardCase(
          ForwardEdgeRepository(database),
          _NoopForwardAttribution(),
          helpOffers,
          InboxRepository(database),
          CapabilityEvidenceRepository(database),
          BeaconRepository(database),
          FakeUserBlockRepository(),
          _AllVisiblePeers(),
          FakeBeaconAccessGuard(),
          attention: TransactionalAttentionCase(unitOfWork, dispatch),
          attentionIntents: AttentionIntentCase(
            BeaconRoomNotificationContextRepository(
              BeaconRoomRepository(database),
              database,
              helpOffers,
              CommitmentRepository(database),
            ),
            UserRepository(
              env,
              database,
              _NoopInviteGenealogyRepository(),
              InviteSeedPromptRepositoryMock(),
            ),
            BeaconAccessRepository(database),
            FakeUserBlockRepository(),
          ),
          env: env,
          logger: logger,
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: database);
      });

      setUp(() async {
        await _resetFixtures(writer);
      });
    }

    Future<int> recipientInsertsFor(
      int recipientCount, {
      String sourceEventKey = 'forward',
    }) async {
      final intent = _intent(
        sourceEventKey: '$sourceEventKey-$recipientCount',
        recipients: _variedRecipients(recipientCount),
      );
      recorder.reset();
      await unitOfWork.run(
        actorUserId: _actorId,
        action: () => dispatch.record(intent),
      );
      return recorder.countMatching(_recipientInsert);
    }

    test(
      'the number of statements writing recipient snapshots does not grow '
      'with the number of people forwarded to',
      () async {
        final small = await recipientInsertsFor(2);
        final large = await recipientInsertsFor(_manyRecipients);

        expect(
          large,
          small,
          reason:
              '2 recipients took $small recipient INSERTs, '
              '$_manyRecipients took $large',
        );
        expect(
          await _count(writer, 'public.attention_occurrence_recipient'),
          2 + _manyRecipients,
          reason: 'every recipient still gets a snapshot row',
        );
      },
      skip: skipReason,
    );

    test(
      'forwarding to many people stores every recipient snapshot exactly as '
      'the per-recipient path did',
      () async {
        await recipientInsertsFor(_manyRecipients);

        await _expectSnapshots(writer, {
          for (var i = 0; i < _manyRecipients; i++)
            _recipientId(i): _variedExpected(i),
        });
      },
      skip: skipReason,
    );

    test(
      'each recipient snapshot keeps its own reasons, role facts, collapse '
      'key and channel eligibility',
      () async {
        await unitOfWork.run(
          actorUserId: _actorId,
          action: () => dispatch.record(
            _intent(
              sourceEventKey: 'forward-mixed',
              recipients: _mixedRecipients(),
            ),
          ),
        );

        await _expectSnapshots(writer, _mixedExpected);
        expect(
          await _count(writer, 'public.attention_occurrence'),
          1,
          reason: 'all snapshots belong to the one occurrence',
        );
      },
      skip: skipReason,
    );

    Future<int> forwardInsertsFor(List<String> recipientIds) async {
      recorder.reset();
      await forwardCase.forward(
        senderId: _actorId,
        beaconId: _beaconId,
        recipientIds: recipientIds,
      );
      return recorder.countMatching(_recipientInsert);
    }

    test(
      'forwarding a Request: the number of statements writing recipient '
      'snapshots does not grow with the number of people forwarded to',
      () async {
        final small = await forwardInsertsFor([
          for (var i = 0; i < 2; i++) _recipientId(i),
        ]);
        final large = await forwardInsertsFor([
          for (var i = 2; i < 2 + _manyRecipients - 2; i++) _recipientId(i),
        ]);

        expect(
          large,
          small,
          reason:
              '2 recipients took $small recipient INSERTs, '
              '${_manyRecipients - 2} took $large',
        );
        expect(
          await _count(writer, 'public.attention_occurrence_recipient'),
          _manyRecipients,
          reason: 'every person forwarded to still gets a snapshot row',
        );
      },
      skip: skipReason,
    );

    test(
      'forwarding a Request stores one identical snapshot per person, '
      'under one occurrence',
      () async {
        final recipients = [
          for (var i = 0; i < _manyRecipients; i++) _recipientId(i),
        ];
        await forwardCase.forward(
          senderId: _actorId,
          beaconId: _beaconId,
          recipientIds: recipients,
          sharedNote: 'Could you look at this?',
        );

        // The forward's collapse key embeds its generated batch id; every
        // person in the batch shares it.
        final collapseKey = (await _snapshots(
          writer,
        )).values.first['collapse_key'];
        expect(collapseKey, matches(r'^v1\|none\|forward_batch%3A'));
        await _expectSnapshots(writer, {
          for (final id in recipients)
            id: {
              'reasons': ['forwardRecipient'],
              'role_facts': _roleFacts(excerpt: 'Could you look at this?'),
              'collapse_key': collapseKey,
              'channel_eligible': true,
            },
        });
        expect(await _count(writer, 'public.attention_occurrence'), 1);
      },
      skip: skipReason,
    );
  }, skip: skipReason);
}

/// Records the SQL text of every statement Drift sends, so a test can count
/// only the statements it cares about.
class _StatementRecorder extends QueryInterceptor {
  final _statements = <String>[];

  void reset() => _statements.clear();

  int countMatching(Pattern pattern) =>
      _statements.where((sql) => sql.contains(pattern)).length;

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
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

final _recipientInsert = RegExp(
  r'INSERT\s+INTO\s+(public\.)?attention_occurrence_recipient\b',
  caseSensitive: false,
);

const _actorId = 'Ubatchactor';
const _beaconId = 'Bbatchcontent';
const _collapseKey = 'relay|$_beaconId';
const _manyRecipients = 12;

String _recipientId(int i) => 'Ubatchrecipient$i';

/// Recipients cycling through four shapes, so every stored column varies
/// across a batch and a batched write that mixes rows up, or applies one
/// recipient's values to all, is visible:
///  0 — plain forward recipient, role facts filled from the intent;
///  1 — two reasons, its own collapse key, not channel eligible;
///  2 — title and excerpt that need JSON escaping, unique per recipient;
///  3 — a role carrying every own fact, which the intent must not overwrite.
List<AttentionRecipientSnapshot> _variedRecipients(int count) => [
  for (var i = 0; i < count; i++)
    switch (i % 4) {
      0 => AttentionRecipientSnapshot(
        recipientId: _recipientId(i),
        reasons: const {AttentionRecipientReason.forwardRecipient},
        role: const AttentionRecipientRoleFacts(canReadBeaconContent: true),
      ),
      1 => AttentionRecipientSnapshot(
        recipientId: _recipientId(i),
        reasons: const {
          AttentionRecipientReason.forwardRecipient,
          AttentionRecipientReason.inboxStanceHolder,
        },
        role: const AttentionRecipientRoleFacts(canReadBeaconContent: true),
        collapseKey: 'relay|recipient-$i',
        channelEligible: false,
      ),
      2 => AttentionRecipientSnapshot(
        recipientId: _recipientId(i),
        reasons: const {AttentionRecipientReason.forwardRecipient},
        role: AttentionRecipientRoleFacts(
          canReadBeaconContent: true,
          beaconTitle: 'Title #$i with "quotes" and ünïcode',
          excerpt: 'Note $i: a, b; c\nsecond line',
        ),
      ),
      _ => AttentionRecipientSnapshot(
        recipientId: _recipientId(i),
        reasons: const {AttentionRecipientReason.inboxStanceHolder},
        role: AttentionRecipientRoleFacts(
          beaconId: 'Bown$i',
          coordinationItemId: 'Citem$i',
          targetEntityId: 'Ttarget$i',
          messageId: 'Mmessage$i',
          actorUserId: 'Uown$i',
          trustDirection: 'up',
          inviteOrigin: 'existing_account',
          toStatus: 'open',
          withdrawReason: 'busy',
          leftDiscussion: true,
          nextStepMentionsActor: false,
        ),
      ),
    },
];

/// What the per-recipient path stored for recipient [i] of
/// [_variedRecipients]: the intent's beacon and actor fill the role facts a
/// recipient left empty, and a recipient's own collapse key wins over the
/// intent's. Captured from the one-INSERT-per-recipient implementation.
Map<String, Object?> _variedExpected(int i) => switch (i % 4) {
  0 => {
    'reasons': ['forwardRecipient'],
    'role_facts': _roleFacts(),
    'collapse_key': _collapseKey,
    'channel_eligible': true,
  },
  1 => {
    'reasons': ['forwardRecipient', 'inboxStanceHolder'],
    'role_facts': _roleFacts(),
    'collapse_key': 'relay|recipient-$i',
    'channel_eligible': false,
  },
  2 => {
    'reasons': ['forwardRecipient'],
    'role_facts': _roleFacts(
      beaconTitle: 'Title #$i with "quotes" and ünïcode',
      excerpt: 'Note $i: a, b; c\nsecond line',
    ),
    'collapse_key': _collapseKey,
    'channel_eligible': true,
  },
  _ => {
    'reasons': ['inboxStanceHolder'],
    'role_facts': {
      'canReadBeaconContent': false,
      'beaconId': 'Bown$i',
      'coordinationItemId': 'Citem$i',
      'targetEntityId': 'Ttarget$i',
      'messageId': 'Mmessage$i',
      'actorUserId': 'Uown$i',
      'beaconTitle': null,
      'trustDirection': 'up',
      'inviteOrigin': 'existing_account',
      'excerpt': null,
      'toStatus': 'open',
      'withdrawReason': 'busy',
      'leftDiscussion': true,
      'nextStepMentionsActor': false,
    },
    'collapse_key': _collapseKey,
    'channel_eligible': true,
  },
};

/// Recipients that differ in every stored column.
List<AttentionRecipientSnapshot> _mixedRecipients() => const [
  AttentionRecipientSnapshot(
    recipientId: 'Ubatchrecipient0',
    reasons: {AttentionRecipientReason.forwardRecipient},
    role: AttentionRecipientRoleFacts(canReadBeaconContent: true),
  ),
  AttentionRecipientSnapshot(
    recipientId: 'Ubatchrecipient1',
    reasons: {
      AttentionRecipientReason.forwardRecipient,
      AttentionRecipientReason.inboxStanceHolder,
    },
    role: AttentionRecipientRoleFacts(canReadBeaconContent: true),
    collapseKey: 'relay|recipient-specific',
    channelEligible: false,
  ),
  AttentionRecipientSnapshot(
    recipientId: 'Ubatchrecipient2',
    reasons: {AttentionRecipientReason.forwardRecipient},
    role: AttentionRecipientRoleFacts(
      canReadBeaconContent: true,
      beaconTitle: 'Title with "quotes" and ünïcode',
      excerpt: 'Note: a, b; c\nsecond line',
    ),
  ),
];

/// What the per-recipient path stored for [_mixedRecipients]: the intent's
/// beacon and actor fill the role facts a recipient left empty, and a
/// recipient's own collapse key wins over the intent's.
final _mixedExpected = <String, Map<String, Object?>>{
  'Ubatchrecipient0': {
    'reasons': ['forwardRecipient'],
    'role_facts': _roleFacts(),
    'collapse_key': _collapseKey,
    'channel_eligible': true,
  },
  'Ubatchrecipient1': {
    'reasons': ['forwardRecipient', 'inboxStanceHolder'],
    'role_facts': _roleFacts(),
    'collapse_key': 'relay|recipient-specific',
    'channel_eligible': false,
  },
  'Ubatchrecipient2': {
    'reasons': ['forwardRecipient'],
    'role_facts': _roleFacts(
      beaconTitle: 'Title with "quotes" and ünïcode',
      excerpt: 'Note: a, b; c\nsecond line',
    ),
    'collapse_key': _collapseKey,
    'channel_eligible': true,
  },
};

Map<String, Object?> _roleFacts({String? beaconTitle, String? excerpt}) => {
  'canReadBeaconContent': true,
  'beaconId': _beaconId,
  'coordinationItemId': null,
  'targetEntityId': null,
  'messageId': null,
  'actorUserId': _actorId,
  'beaconTitle': beaconTitle,
  'trustDirection': null,
  'inviteOrigin': null,
  'excerpt': excerpt,
  'toStatus': null,
  'withdrawReason': null,
  'leftDiscussion': null,
  'nextStepMentionsActor': null,
};

AttentionDispatchIntent _intent({
  required String sourceEventKey,
  required List<AttentionRecipientSnapshot> recipients,
}) => AttentionDispatchIntent(
  eventType: AttentionEventType.relayReceived,
  sourceEventKey: sourceEventKey,
  actorUserId: _actorId,
  priority: NotificationPriority.normal,
  kind: NotificationKind.newRelay,
  title: 'Forwarded Request',
  body: 'A Request was forwarded to you',
  actionUrl: '/#/view?id=$_beaconId',
  collapseKey: _collapseKey,
  recipients: recipients,
  beaconId: _beaconId,
);

/// Stored snapshots keyed by account, with the jsonb columns decoded so the
/// comparison does not depend on Postgres' jsonb text formatting.
Future<Map<String, Map<String, Object?>>> _snapshots(Connection writer) async {
  final rows = await writer.execute('''
SELECT account_id, reasons::text AS reasons,
       role_facts::text AS role_facts, collapse_key, channel_eligible
FROM public.attention_occurrence_recipient
''');
  return {
    for (final row in rows)
      row.toColumnMap()['account_id']! as String: {
        'reasons': jsonDecode(row.toColumnMap()['reasons']! as String),
        'role_facts': jsonDecode(row.toColumnMap()['role_facts']! as String),
        'collapse_key': row.toColumnMap()['collapse_key'],
        'channel_eligible': row.toColumnMap()['channel_eligible'],
      },
  };
}

Future<void> _expectSnapshots(
  Connection writer,
  Map<String, Map<String, Object?>> expected,
) async {
  final rows = await _snapshots(writer);
  expect(rows.keys, unorderedEquals(expected.keys));
  for (final entry in expected.entries) {
    expect(rows[entry.key], entry.value, reason: entry.key);
  }
}

Future<int> _count(Connection writer, String table) async {
  final rows = await writer.execute('SELECT count(*)::int FROM $table');
  return rows.single.single! as int;
}

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.attention_channel_delivery,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (id, key) in [
    (_actorId, 'batch-actor-key'),
    for (var i = 0; i < _manyRecipients; i++)
      (_recipientId(i), 'batch-recipient-key-$i'),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': key},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beaconId, @actorId, 'Readable', 'Readable request', 0)
'''),
    parameters: {'beaconId': _beaconId, 'actorId': _actorId},
  );
}

class _AllVisiblePeers extends Fake implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}

class _NoopForwardAttribution extends Fake
    implements ForwardAttributionRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
