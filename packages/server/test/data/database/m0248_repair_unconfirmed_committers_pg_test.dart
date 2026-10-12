@Tags(['pg'])
library;

import 'dart:async';

import 'package:async/async.dart' show StreamSinkTransformer;
import 'package:logging/logging.dart';
import 'package:postgres/messages.dart'
    show ErrorFieldId, Message, NoticeMessage;
import 'package:postgres/postgres.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dismissible_sql.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// m0248 (budding E2, Arch §10, I1): every open-family Request (`kind = 0`,
/// status 0 / 7 / 8) whose admitted non-author, non-steward participant never
/// acknowledged is repaired.
///
/// - an offer without an ack keeps the offer and loses room access;
/// - no own confirmation loses room access (role-6 rows are deleted) and gets
///   a pending warm author invite with no source Post, riding the person's
///   latest active inbound edge, or a new exempt author → person edge;
/// - anyone who acknowledged at least once, stewards and the author are left
///   alone, as are Requests in review (status 5) or closed (status 6).
const _author = 'Um0247author01';
const _sender = 'Um0247sender01';
const _steward = 'Um0247steward1';
const _offerer = 'Um0247offerer1';
const _noEdge = 'Um0247noedge01';
const _withEdge = 'Um0247withedge1';
const _addressee = 'Um0247addrssee1';
const _acked = 'Um0247acked001';
const _ackedThenLeft = 'Um0247ackleft01';
const _needsHelp = 'Um0247needs0001';
const _enoughHelp = 'Um0247enough001';
const _historicalAdmit = 'Um0247histadmit1';
const _review = 'Um0247review001';
const _closed = 'Um0247closed001';
const _users = [
  _author,
  _sender,
  _steward,
  _offerer,
  _noEdge,
  _withEdge,
  _addressee,
  _acked,
  _ackedThenLeft,
  _needsHelp,
  _enoughHelp,
  _historicalAdmit,
  _review,
  _closed,
];

const _open = 'Bm0247open00001';
const _needsHelpBeacon = 'Bm0247needs0001';
const _enoughHelpBeacon = 'Bm0247enough001';
const _reviewBeacon = 'Bm0247review001';
const _closedBeacon = 'Bm0247closed001';

const _oldEdge = 'Fm0247oldedge01';
const _latestEdge = 'Fm0247latest001';
const _cancelledEdge = 'Fm0247cancelled1';
const _addresseeEdge = 'Fm0247addrssee1';

/// The author's live `helpOfferSubmitted` obligation for the offerer's offer.
const _obligation = 'Nm0247oblig0001';

const _statusOpen = 0;
const _roleHelper = 2;
const _roleAddressee = 6;
const _admitted = 3;

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0248_REPAIR_UNCONFIRMED_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0248_repair_mig',
  );
  final pgSkip = await pgSkipReason(migrationTarget);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late String versionBeforeUpgrade;
    late int violatorsBeforeUpgrade;
    late int invitesBeforeUpgrade;
    final notices = <String>[];

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0247',
      );
      writer = session.writer;
      await _seed(writer);
      versionBeforeUpgrade =
          (await writer.execute(
                'SELECT max(version COLLATE "C") FROM schema_version',
              )).single.single!
              as String;
      violatorsBeforeUpgrade = (await _violators(writer)).length;
      invitesBeforeUpgrade =
          (await writer.execute(
                'SELECT count(*) FROM public.beacon_author_invite',
              )).single.single!
              as int;

      // Upgrade on a connection that records server notices (the report).
      final upgrader = await Connection.open(
        migrationTarget.databaseEnv.pgEndpoint,
        settings: ConnectionSettings(
          sslMode: SslMode.disable,
          transformer: _noticeRecorder(notices),
        ),
      );
      try {
        await upgrader.execute('SET check_function_bodies = false');
        await migrateDbSchema(upgrader);
      } finally {
        await upgrader.close();
      }
      database = openDisposablePgDatabase(migrationTarget);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('the fixtures were written under the previous schema version, with '
        'violators and no repair invites yet', () {
      expect(versionBeforeUpgrade, '0247');
      expect(violatorsBeforeUpgrade, greaterThanOrEqualTo(7));
      expect(invitesBeforeUpgrade, 0);
    });

    test(
      'an offer without an ack stays an offer but loses room access',
      () async {
        final offer = await writer.execute(
          'SELECT status FROM public.beacon_help_offer '
          "WHERE beacon_id = '$_open' AND user_id = '$_offerer'",
        );
        expect(offer.single.single, 0);

        final participant = await _participant(writer, _open, _offerer);
        expect(participant, isNotNull);
        expect(participant!.access, isNot(_admitted));
        expect(await _invites(writer, _open, _offerer), isEmpty);
      },
    );

    test('the author obligation of an offer without an ack is kept', () async {
      final rows = await writer.execute(
        'SELECT requires_action, settlement_kind, cleared_at '
        "FROM public.notification_outbox WHERE id = '$_obligation'",
      );
      expect(rows.single.toList(), [true, null, null]);
    });

    test(
      'a reused unresolved repair edge produces no noisy evidence',
      () async {
        final invite = (await _invites(writer, _open, _withEdge)).single;
        expect(invite.warm, isTrue);
        expect(invite.forwardEdge, _latestEdge);

        final before = await writer.execute(
          'SELECT contact_outcome, contact_resolved_at, contact_deadline_at '
          "FROM public.beacon_forward_edge WHERE id = '$_latestEdge'",
        );
        expect(before.single[0], isNull);
        expect(before.single[1], isNull);
        expect(before.single[2], isNotNull);

        await writer.execute(
          'UPDATE public.beacon_forward_edge '
          "SET contact_deadline_at = now() - interval '1 hour' "
          "WHERE id = '$_latestEdge'",
        );
        await ContactResolutionSweepCase(
          unitOfWork: MutatingUnitOfWork(database),
          forwardEdgeRepository: ForwardEdgeRepository(database),
          trustLedger: TrustLedgerRepository(database),
          env: migrationTarget.databaseEnv,
          logger: Logger('M0248RepairSweepPgTest'),
        ).run();

        final after = await writer.execute(
          'SELECT contact_outcome, contact_resolved_at '
          "FROM public.beacon_forward_edge WHERE id = '$_latestEdge'",
        );
        expect(after.single.toList(), [null, null]);
        final evidence = await writer.execute(
          'SELECT source_key FROM public.trust_evidence '
          "WHERE source_key LIKE 'contact:$_latestEdge:%'",
        );
        expect(evidence, isEmpty);
      },
    );

    test('a person who never confirmed loses room access', () async {
      for (final user in [_noEdge, _withEdge, _historicalAdmit]) {
        final participant = await _participant(writer, _open, user);
        expect(participant?.access, isNot(_admitted), reason: user);
      }
    });

    test('a role-6 addressee has its participant row deleted', () async {
      expect(await _participant(writer, _open, _addressee), isNull);
    });

    test('an unconfirmed person gets a pending warm repair invite '
        'from the Request author', () async {
      for (final user in [_noEdge, _withEdge, _addressee, _historicalAdmit]) {
        final invites = await _invites(writer, _open, user);
        expect(invites, hasLength(1), reason: user);
        final invite = invites.single;
        expect(invite.status, 0, reason: user);
        expect(invite.inviter, _author, reason: user);
        expect(invite.sourcePost, isNull, reason: user);
        expect(invite.arrivalPostEdge, isNull, reason: user);
        expect(invite.warm, isTrue, reason: user);
        expect(invite.forwardEdge, isNotNull, reason: user);
      }
    });

    test('the repair invite rides the latest active inbound edge', () async {
      final invite = (await _invites(writer, _open, _withEdge)).single;
      expect(invite.forwardEdge, _latestEdge);
      expect(
        await writer.execute(
          'SELECT count(*) FROM public.beacon_forward_edge '
          "WHERE beacon_id = '$_open' AND recipient_id = '$_withEdge'",
        ),
        [
          [3],
        ],
        reason: 'an existing edge is reused, none is added',
      );

      final addressee = (await _invites(writer, _open, _addressee)).single;
      expect(addressee.forwardEdge, _addresseeEdge);
    });

    test('a person with no inbound edge gets an exempt author edge', () async {
      final invite = (await _invites(writer, _open, _noEdge)).single;
      final edge = await writer.execute(
        'SELECT sender_id, recipient_id, beacon_id, cancelled_at, '
        'contact_sweep_exempt FROM public.beacon_forward_edge '
        "WHERE id = '${invite.forwardEdge}'",
      );
      expect(edge.single.toList(), [_author, _noEdge, _open, null, true]);
    });

    test('the inbox row of a repaired person asks for attention', () async {
      for (final user in [_noEdge, _withEdge, _addressee, _historicalAdmit]) {
        final rows = await writer.execute(
          'SELECT status FROM public.inbox_item '
          "WHERE beacon_id = '$_open' AND user_id = '$user'",
        );
        expect(rows.single.single, 0, reason: user);
      }
    });

    test('repair sends no notification', () async {
      final outbox = await writer.execute(
        'SELECT id FROM public.notification_outbox',
      );
      expect(
        outbox.map((r) => r.single),
        [_obligation],
        reason: 'only the receipt seeded before the upgrade',
      );
      final occurrences = await writer.execute(
        'SELECT count(*) FROM public.attention_occurrence',
      );
      expect(occurrences.single.single, 0);
    });

    test('a repaired person with no prior edge can read the Request and sees '
        'it pinned', () async {
      for (final user in [_noEdge, _withEdge, _addressee, _historicalAdmit]) {
        final canRead = await writer.execute(
          Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
          parameters: {'b': _open, 'u': user},
        );
        expect(canRead.single.single, isTrue, reason: user);
        expect(await _eligiblePinned(writer, user), contains(_open));

        final offers = await AttentionRepository(
          database,
        ).activityOffers(accountId: user);
        final row = offers.items.singleWhere((i) => i.beaconId == _open);
        final invite = (await _invites(writer, _open, user)).single;
        expect(row.inviteId, invite.id, reason: user);
      }
    });

    test('a Request in another open status is repaired too', () async {
      expect(
        (await _participant(writer, _needsHelpBeacon, _needsHelp))?.access,
        isNot(_admitted),
      );
      expect(
        await _invites(writer, _needsHelpBeacon, _needsHelp),
        hasLength(1),
      );
    });

    test('a Request that enough help was offered on is repaired too', () async {
      expect(
        (await _participant(writer, _enoughHelpBeacon, _enoughHelp))?.access,
        isNot(_admitted),
      );
      expect(
        await _invites(writer, _enoughHelpBeacon, _enoughHelp),
        hasLength(1),
      );
    });

    test('a historical admit by the author is repaired like any other '
        'unconfirmed person', () async {
      final invite = (await _invites(writer, _open, _historicalAdmit)).single;
      expect(invite.sourcePost, isNull);
      expect(invite.forwardEdge, isNotNull);
    });

    test('the migration reports repaired counts per class and lists the '
        'skipped review and closed Requests', () {
      final report = notices.join('\n');
      expect(report, isNotEmpty, reason: 'the upgrade raised no NOTICE');
      int? countOf(String keyword) {
        for (final line in report.split('\n')) {
          if (!line.toLowerCase().contains(keyword)) continue;
          final number = RegExp(r'\d+').firstMatch(line);
          if (number != null) return int.parse(number.group(0)!);
        }
        return null;
      }

      expect(countOf('offer'), 1, reason: 'offer without an ack: $report');
      expect(countOf('confirm'), 6, reason: 'no own confirmation: $report');
      expect(report, contains(_reviewBeacon));
      expect(report, contains(_closedBeacon));
    });

    test('anyone who acknowledged once is left untouched', () async {
      for (final user in [_acked, _ackedThenLeft]) {
        final participant = await _participant(writer, _open, user);
        expect(participant?.role, _roleHelper, reason: user);
        expect(participant?.access, _admitted, reason: user);
        expect(await _invites(writer, _open, user), isEmpty, reason: user);
      }
    });

    test('the author and a steward are left untouched', () async {
      expect((await _participant(writer, _open, _steward))?.access, _admitted);
      expect(await _invites(writer, _open, _steward), isEmpty);
      expect(await _invites(writer, _open, _author), isEmpty);
    });

    test('a Request in review or closed is not modified', () async {
      for (final (beacon, user) in [
        (_reviewBeacon, _review),
        (_closedBeacon, _closed),
      ]) {
        final participant = await _participant(writer, beacon, user);
        expect(participant?.access, _admitted, reason: beacon);
        expect(await _invites(writer, beacon, user), isEmpty, reason: beacon);
      }
    });

    test(
      'no open-family Request has an admitted committer without an ack',
      () async {
        final violators = await _violators(writer);
        expect(violators, isEmpty);
      },
    );
  });
}

Future<List<ResultRow>> _violators(Connection writer) => writer.execute('''
SELECT bp.beacon_id, bp.user_id
FROM public.beacon_participant bp
JOIN public.beacon b ON b.id = bp.beacon_id
WHERE b.kind = 0
  AND b.status IN (0, 7, 8)
  AND bp.room_access = 3
  AND bp.user_id <> b.user_id
  AND bp.role NOT IN (0, 1)
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_commitment_event ce
    WHERE ce.beacon_id = bp.beacon_id AND ce.user_id = bp.user_id
      AND ce.kind = 1)
''');

Future<void> _seed(Connection writer) async {
  await writer.execute(
    'TRUNCATE TABLE public.beacon, public."user" CASCADE',
  );
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': _users[i],
        'key': i < 9
            ? pgTestPublicKey('m0248', i + 1)
            : pgTestPublicKey('q0247', i - 8),
      },
    );
  }
  for (final (id, status) in [
    (_open, _statusOpen),
    (_needsHelpBeacon, 7),
    (_enoughHelpBeacon, 8),
    (_reviewBeacon, 5),
    (_closedBeacon, 6),
  ]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES ('$id', '$_author', 'Move the piano', 'Saturday', $status, false, now())
''');
  }

  // Inbound edges: the person with an edge has an old one, the latest active
  // one and a newer cancelled one.
  await _edge(writer, _oldEdge, _open, _withEdge, '2 days', sender: _steward);
  await _edge(writer, _latestEdge, _open, _withEdge, '1 day');
  await _edge(
    writer,
    _cancelledEdge,
    _open,
    _withEdge,
    '1 hour',
    cancelled: true,
  );
  await _edge(writer, _addresseeEdge, _open, _addressee, '1 day');
  await _edge(
    writer,
    'Fm0247needs00001',
    _needsHelpBeacon,
    _needsHelp,
    '1 day',
  );
  await writer.execute(
    'UPDATE public.inbox_item SET status = 1 '
    "WHERE user_id IN ('$_withEdge', '$_addressee')",
  );

  Future<void> participant(
    String beacon,
    String user,
    int role,
  ) => writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$beacon', '$user', $role, $_admitted)
''');

  await participant(_open, _author, 0);
  await participant(_open, _steward, 1);
  for (final user in [_offerer, _noEdge, _withEdge, _acked, _ackedThenLeft]) {
    await participant(_open, user, _roleHelper);
  }
  await participant(_open, _addressee, _roleAddressee);
  await participant(_needsHelpBeacon, _needsHelp, _roleHelper);
  await participant(_enoughHelpBeacon, _enoughHelp, _roleHelper);
  // A historical `BeaconRoomAdmit` admit: admitted by the author with the
  // `admit` reason, no offer, no commitment event, no inbound edge.
  await participant(_open, _historicalAdmit, _roleHelper);
  await writer.execute('''
INSERT INTO public.beacon_activity_event
  (beacon_id, visibility, type, actor_id, target_user_id, diff)
VALUES ('$_open', 0, ${BeaconActivityEventTypeBits.participantJoined},
        '$_author', '$_historicalAdmit', '{"admissionReason": "admit"}'::jsonb)
''');
  await participant(_reviewBeacon, _review, _roleHelper);
  await participant(_closedBeacon, _closed, _roleHelper);

  await writer.execute('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status)
VALUES ('$_open', '$_offerer', 0), ('$_open', '$_acked', 0),
       ('$_open', '$_ackedThenLeft', 0)
''');

  await writer.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, beacon_id,
  actor_user_id, title, body, action_url, dedup_key, source_event_key,
  destination_kind, presentation_key, access_policy, requires_action,
  attention_thread_key
) VALUES (
  '$_obligation', '$_author', 'coordination', 'helpOfferSubmitted', 'normal',
  '$_open', '$_offerer', 'Offer', 'An offer', '/attention', 'dedup-$_obligation',
  'source-$_obligation', 'beacon', 'help_offer_submitted', 'beacon_content',
  true, 'v1|a|b|c')
''');

  var seq = 0;
  Future<void> event(String beacon, String user, int kind) => writer.execute('''
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, kind)
VALUES ('Em0247${(++seq).toString().padLeft(6, '0')}', '$beacon', '$user', $kind)
''');
  await event(_open, _offerer, 0);
  await event(_open, _acked, 0);
  await event(_open, _acked, 1);
  await event(_open, _ackedThenLeft, 1);
  await event(_open, _ackedThenLeft, 3);
}

Future<void> _edge(
  Connection writer,
  String id,
  String beacon,
  String recipient,
  String age, {
  bool cancelled = false,
  String sender = _sender,
}) => writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at, cancelled_at)
VALUES ('$id', '$beacon', '$sender', '$recipient', now() - interval '$age',
        ${cancelled ? 'now()' : 'NULL'})
''');

typedef _Participant = ({int role, int access});

Future<_Participant?> _participant(
  Connection writer,
  String beacon,
  String user,
) async {
  final rows = await writer.execute('''
SELECT role, room_access FROM public.beacon_participant
WHERE beacon_id = '$beacon' AND user_id = '$user'
''');
  if (rows.isEmpty) return null;
  return (role: rows.single[0]! as int, access: rows.single[1]! as int);
}

typedef _Invite = ({
  String id,
  int status,
  String inviter,
  String? sourcePost,
  String? arrivalPostEdge,
  bool warm,
  String? forwardEdge,
});

Future<List<_Invite>> _invites(
  Connection writer,
  String beacon,
  String user,
) async {
  final rows = await writer.execute('''
SELECT status, inviter_id, source_post_id, arrival_post_edge_id, warm,
       forward_edge_id, id
FROM public.beacon_author_invite
WHERE beacon_id = '$beacon' AND invitee_id = '$user'
''');
  return [
    for (final r in rows)
      (
        status: r[0]! as int,
        inviter: r[1]! as String,
        sourcePost: r[2] as String?,
        arrivalPostEdge: r[3] as String?,
        warm: r[4]! as bool,
        forwardEdge: r[5] as String?,
        id: r[6]! as String,
      ),
  ];
}

Future<Set<String>> _eligiblePinned(Connection writer, String viewer) async {
  final rows = await writer.execute(
    'WITH ${AttentionDismissibleSql.prelude} '
    'SELECT beacon_id FROM eligible_pinned',
    parameters: [viewer],
  );
  return {for (final r in rows) r[0]! as String};
}

/// Records the text of every server NOTICE passing through a connection.
StreamChannelTransformer<Message, Message> _noticeRecorder(
  List<String> notices,
) => StreamChannelTransformer<Message, Message>(
  StreamTransformer<Message, Message>.fromHandlers(
    handleData: (message, sink) {
      if (message is NoticeMessage) {
        for (final field in message.fields) {
          if (field.id == ErrorFieldId.message) notices.add(field.text);
        }
      }
      sink.add(message);
    },
  ),
  StreamSinkTransformer<Message, Message>.fromHandlers(
    handleData: (message, sink) => sink.add(message),
  ),
);
