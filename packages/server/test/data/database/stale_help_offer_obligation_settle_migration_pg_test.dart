@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_reconciliation_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';

import '../../support/disposable_pg_target.dart';

/// Stale «new help offer» obligations — live `help_offer_submitted` rows the
/// author can no longer act on, because the offer was already admitted or is
/// gone — are settled by a forward migration and by the author's own read of
/// their attention, never only by the manual reconcile endpoint.
///
/// The migration settles every account in one pass with the same rule as
/// `AttentionReconciliationRepository.settleObsoleteHelpOfferObligations`:
/// an answered offer is `resolved`, a withdrawn or missing one is
/// `superseded`, an offer still waiting for the author stays live.

/// The migration that settles the stale rows comes right after the last
/// shipped one; a shipped migration is never edited.
const _lastShippedVersion = '0314';
const _settleVersion = '0315';
const _migrationDir = 'lib/data/database/migration';

/// Frozen fingerprints of every shipped migration (m0193 … m0314, the
/// registry starts at the m0193 squash). A shipped migration is never edited,
/// so these never change; a fix to an old migration needs a new one.
const _shippedMigrationCount = 121;
const _shippedStatementsSha256 =
    '604cccc0dec85800c41df58fc55a4e1679f10080fce0beed0667a033282efbff';
const _shippedFilesSha256 =
    '4ce0d3bd4c1cb075b1a0e57402a35ac8cf18972a0a1de0d2819b1e7ce68c72a9';

/// One stale-obligation case: the offer's state and what the row must become.
enum _Case {
  acknowledged('ak', 'resolved'),
  softened('sf', 'resolved'),
  released('rl', 'resolved'),
  admittedStatus('ad', 'resolved'),

  /// Offered, withdrew, offered again: the new offer waits for the author.
  reofferedAfterWithdrawal('rw', null),

  /// Offered, admitted, withdrew, offered again: the earlier admission does
  /// not answer the new offer.
  reofferedAfterAdmission('ra', null),

  /// Offered, withdrew, offered again, then admitted.
  admittedAfterReoffer('rr', 'resolved'),

  /// Offered, admitted, offered again, then withdrew.
  withdrawnAfterReoffer('rs', 'superseded'),
  withdrawnReason('wr', 'superseded'),
  withdrawnEvent('we', 'superseded'),
  missingOffer('mo', 'superseded'),
  pending('pe', null),
  userDismissed('ud', 'dismissed'),
  optionalReceipt('op', null),

  /// A pending offer on a closed Request. No expected outcome is pinned
  /// here: it is seeded only in the migration/repository agreement test,
  /// where whatever the shared rule does, both paths must do the same.
  closedRequest('cl', null);

  const _Case(this.code, this.expected);

  final String code;
  final String? expected;
}

/// The cases whose outcome the migration tests pin.
final _pinnedCases = _Case.values
    .where((c) => c != _Case.closedRequest)
    .toSet();

const _settledByMigration = [
  _Case.acknowledged,
  _Case.softened,
  _Case.released,
  _Case.admittedStatus,
  _Case.admittedAfterReoffer,
  _Case.withdrawnAfterReoffer,
  _Case.withdrawnReason,
  _Case.withdrawnEvent,
  _Case.missingOffer,
];

String _author(String a) => 'Ustlo${a}auth01';
String _helper(String a, _Case c) => 'Ustlo${a}h${c.code}01';
String _beacon(String a, _Case c) => 'Bstlo$a${c.code}01';
String _receiptId(String a, _Case c) => 'Nstlo$a${c.code}';

Future<void> main() async {
  group('migration registry', () {
    test(
      'one new migration, m0315.dart, is a part of the registry and runs '
      'right after the last shipped one',
      () {
        expect(
          File('$_migrationDir/m0315.dart').existsSync(),
          isTrue,
          reason: 'the settle migration lives in its own new file',
        );
        expect(
          File('$_migrationDir/_migrations.dart').readAsStringSync(),
          contains("part 'm0315.dart';"),
        );
        final versions = [for (final m in migrationsForTesting) m.version];
        final shipped = versions.indexOf(_lastShippedVersion);
        expect(shipped, isNonNegative);
        expect(
          versions.length,
          greaterThan(shipped + 1),
          reason: 'no migration is registered after $_lastShippedVersion',
        );
        expect(versions[shipped + 1], _settleVersion);
      },
    );

    test(
      'm0315 carries its SQL as a frozen literal, so a later change to the '
      'shared settle rule never rewrites it',
      () {
        final source = File('$_migrationDir/m0315.dart').readAsStringSync();
        expect(
          source,
          isNot(contains('HelpOfferSettlementSql')),
          reason: 'm0315 must not compose the live rule',
        );
        final statements = migrationsForTesting
            .singleWhere((m) => m.version == _settleVersion)
            .statements;
        expect(statements, isNotEmpty);
        for (final statement in statements) {
          expect(
            source,
            contains(statement.trim()),
            reason:
                'every m0315 statement must appear verbatim in m0315.dart, '
                'not be built from other declarations',
          );
        }
      },
    );

    test('shipped migrations m0193 … m0314 are unchanged', () {
      final all = migrationsForTesting;
      final shipped = all.sublist(
        0,
        all.indexWhere((m) => m.version == _lastShippedVersion) + 1,
      );
      expect(shipped, hasLength(_shippedMigrationCount));
      final statements = StringBuffer();
      for (final m in shipped) {
        statements
          ..write(m.version)
          ..write('\u0000');
        for (final s in m.statements) {
          statements
            ..write(s)
            ..write('\u0001');
        }
        statements.write('\u0002');
      }
      expect(
        sha256.convert(utf8.encode(statements.toString())).toString(),
        _shippedStatementsSha256,
        reason: 'the SQL of a shipped migration changed',
      );

      final files =
          Directory(_migrationDir)
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where((name) => RegExp(r'^m\d{4}\.dart$').hasMatch(name))
              .where((name) => int.parse(name.substring(1, 5)) <= 314)
              .toList()
            ..sort();
      expect(files, hasLength(_shippedMigrationCount));
      final bytes = <int>[];
      for (final name in files) {
        bytes
          ..addAll(utf8.encode(name))
          ..add(0)
          ..addAll(File('$_migrationDir/$name').readAsBytesSync())
          ..add(1);
      }
      expect(
        sha256.convert(bytes).toString(),
        _shippedFilesSha256,
        reason: 'a shipped migration file is no longer byte-identical',
      );
    });
  });

  group('the stale help-offer migration on existing rows', () {
    final target = DisposablePgTarget.fromNamedEnvironment(
      envVarName: 'TENTURA_STALE_HELP_OFFER_MIGRATION_PG_TEST_DB',
      defaultNamePrefix: 'tentura_test_stale_offer_mig',
    );
    late DisposablePgWriterSession session;
    late Connection writer;
    late Map<String, List<Object?>> before;
    Future<Map<String, List<Object?>>>? firstRun;

    /// The first migration run, shared by every test of the group, so each
    /// test still passes or fails on its own under `--name` filtering.
    Future<Map<String, List<Object?>>> afterFirstRun() =>
        firstRun ??= () async {
          await _runSettleMigration(writer);
          return _rows(writer);
        }();

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      await _seedAuthor(writer, 'a', only: _pinnedCases);
      await _seedAuthor(writer, 'b', only: _pinnedCases);
      before = await _rows(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test(
      'answered offers become resolved, withdrawn or missing ones '
      'superseded, and an offer still waiting stays live — for every account',
      () async {
        final after = await afterFirstRun();
        for (final a in ['a', 'b']) {
          for (final c in _pinnedCases) {
            expect(
              after[_receiptId(a, c)]![_kindCol],
              c.expected,
              reason: 'author $a, ${c.name}',
            );
          }
          for (final c in _settledByMigration) {
            final row = after[_receiptId(a, c)]!;
            expect(row[_settledAtCol], isNotNull, reason: '${c.name} at');
            expect(row[_settledByCol], isNull, reason: '${c.name} by');
          }
          expect(after[_receiptId(a, _Case.pending)]![_settledAtCol], isNull);
        }
      },
    );

    test(
      'rows already settled by a person and optional receipts are left as '
      'they were; cleared_at and seen_at never move',
      () async {
        final after = await afterFirstRun();
        for (final a in ['a', 'b']) {
          for (final c in [_Case.userDismissed, _Case.optionalReceipt]) {
            expect(
              after[_receiptId(a, c)],
              before[_receiptId(a, c)],
              reason: 'author $a, ${c.name} must not change',
            );
          }
        }
        for (final id in before.keys) {
          expect(
            after[id]![_clearedAtCol],
            before[id]![_clearedAtCol],
            reason: '$id cleared_at',
          );
          expect(
            after[id]![_seenAtCol],
            before[id]![_seenAtCol],
            reason: '$id seen_at',
          );
        }
      },
    );

    test(
      'a second run updates nothing and keeps what the first run wrote',
      () async {
        final afterFirst = await afterFirstRun();
        for (final c in _settledByMigration) {
          expect(
            afterFirst[_receiptId('a', c)]![_kindCol],
            isNotNull,
            reason: 'the first run settles ${c.name}',
          );
        }
        final updated = await _runSettleMigration(writer);
        expect(updated, 0);
        expect(await _rows(writer), afterFirst);
      },
    );
  });

  group('the migration and the reconcile repository agree', () {
    final target = DisposablePgTarget.fromNamedEnvironment(
      envVarName: 'TENTURA_STALE_HELP_OFFER_PARITY_PG_TEST_DB',
      defaultNamePrefix: 'tentura_test_stale_offer_par',
    );
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = TenturaDb(target.databaseEnv);
      // Two authors with the same dataset: one repaired by the repository,
      // the other by the migration.
      await _seedAuthor(writer, 'r');
      await _seedAuthor(writer, 'm');
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test(
      'on the same dataset both leave the same settlement on every row',
      () async {
        await AttentionReconciliationRepository(
          database,
        ).settleObsoleteHelpOfferObligations(accountId: _author('r'));
        // Read before the migration runs: the migration settles every
        // account, so reading afterwards would hide what the repository did.
        final afterRepository = await _rows(writer);
        final byRepository = {
          for (final c in _Case.values)
            c.name: afterRepository[_receiptId('r', c)]![_kindCol],
        };
        expect(
          byRepository[_Case.acknowledged.name],
          'resolved',
          reason: 'the repository settled its author before the migration',
        );

        await _runSettleMigration(writer);
        final afterMigration = await _rows(writer);
        final byMigration = {
          for (final c in _Case.values)
            c.name: afterMigration[_receiptId('m', c)]![_kindCol],
        };
        expect(byMigration, byRepository);
      },
    );
  });

  const readCases = {
    _Case.acknowledged,
    _Case.withdrawnReason,
    _Case.pending,
  };

  /// A fresh database at head, with stale rows seeded after the schema was
  /// built, so the migration cannot be what settles them.
  void readGroup(
    String description,
    String dbPrefix,
    String envVarName,
    Future<void> Function(TenturaDb database, Connection writer) body,
  ) {
    group(description, () {
      final target = DisposablePgTarget.fromNamedEnvironment(
        envVarName: envVarName,
        defaultNamePrefix: dbPrefix,
      );
      late DisposablePgWriterSession session;
      late Connection writer;
      late TenturaDb database;

      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        database = TenturaDb(target.databaseEnv);
        await _seedAuthor(writer, 'q', only: readCases);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: database);
      });

      test(
        'the admitted and withdrawn offers are settled by the read and no '
        'longer count as live; the waiting offer still does — without any '
        'reconcile call',
        () async {
          final beforeRead = await _rows(writer);
          for (final c in readCases) {
            expect(
              beforeRead[_receiptId('q', c)]![_kindCol],
              isNull,
              reason: '${c.name} is live before the author reads',
            );
          }

          await body(database, writer);

          final rows = await _rows(writer);
          expect(
            rows[_receiptId('q', _Case.acknowledged)]![_kindCol],
            'resolved',
          );
          expect(
            rows[_receiptId('q', _Case.withdrawnReason)]![_kindCol],
            'superseded',
          );
          expect(rows[_receiptId('q', _Case.pending)]![_kindCol], isNull);
          expect(rows[_receiptId('q', _Case.pending)]![_settledAtCol], isNull);
          for (final c in [_Case.acknowledged, _Case.withdrawnReason]) {
            final row = rows[_receiptId('q', c)]!;
            expect(
              row[_settledAtCol],
              isNotNull,
              reason: '${c.name}: a settled row records when it settled',
            );
            expect(
              row[_settledByCol],
              isNull,
              reason: '${c.name}: system repair, not the author dismissing',
            );
          }
        },
      );
    });
  }

  readGroup(
    "reading the author's attention summary settles stale help-offer "
        'obligations',
    'tentura_test_stale_offer_read',
    'TENTURA_STALE_HELP_OFFER_READ_PG_TEST_DB',
    (database, _) async {
      final query = AttentionRepository(database);
      final summary = await query.surfaceSummary(accountId: _author('q'));
      expect(
        summary.myDeskCount,
        1,
        reason: 'only the offer still waiting for the author counts as live',
      );
      expect(
        await query.liveObligationBeacons(accountId: _author('q')),
        {_beacon('q', _Case.pending)},
      );
    },
  );

  readGroup(
    "reading the author's My Work attention settles stale help-offer "
        'obligations',
    'tentura_test_stale_offer_mywork',
    'TENTURA_STALE_HELP_OFFER_MYWORK_PG_TEST_DB',
    (database, _) async {
      final projections = await AttentionRepository(database).myWorkAttention(
        accountId: _author('q'),
        beaconIds: {for (final c in readCases) _beacon('q', c)},
      );
      final liveByBeacon = {
        for (final p in projections)
          if (p.liveObligations.isNotEmpty)
            p.beaconId: [for (final o in p.liveObligations) o.id],
      };
      expect(liveByBeacon, {
        _beacon('q', _Case.pending): [_receiptId('q', _Case.pending)],
      });
    },
  );
}

/// Runs the settle migration's statements as they are registered and returns
/// the number of rows they changed.
Future<int> _runSettleMigration(Connection writer) async {
  final matches = migrationsForTesting.where(
    (m) => m.version == _settleVersion,
  );
  if (matches.isEmpty) {
    fail('no migration $_settleVersion is registered');
  }
  var affected = 0;
  for (final statement in matches.single.statements) {
    final result = await writer.execute(statement);
    affected += result.affectedRows;
  }
  return affected;
}

// ---------------------------------------------------------------------------
// fixture
// ---------------------------------------------------------------------------

Future<void> _seedAuthor(
  Connection writer,
  String a, {
  Set<_Case>? only,
}) async {
  final cases = only ?? _Case.values.toSet();
  final author = _author(a);
  await _user(writer, author);
  for (final c in cases) {
    final helper = _helper(a, c);
    final beacon = _beacon(a, c);
    await _user(writer, helper);
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, 'Request', 'desc', @status)
'''),
      parameters: {
        'id': beacon,
        'author': author,
        'status':
            (c == _Case.closedRequest ? BeaconStatus.closed : BeaconStatus.open)
                .smallintValue,
      },
    );
    switch (c) {
      case _Case.acknowledged:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [1]);
      case _Case.softened:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [2]);
      case _Case.released:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [4]);
      case _Case.admittedStatus:
        // As admission leaves it: the offer row stays active, an `offered`
        // event is followed by an `acknowledged` one.
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [0, 1]);
      case _Case.reofferedAfterWithdrawal:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [0, 3, 0]);
      case _Case.reofferedAfterAdmission:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [0, 1, 3, 0]);
      case _Case.admittedAfterReoffer:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [0, 3, 0, 1]);
      case _Case.withdrawnAfterReoffer:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [0, 1, 0, 3]);
      case _Case.withdrawnReason:
        await _offer(
          writer,
          beacon,
          helper,
          status: 1,
          withdrawReason: 'changed mind',
        );
      case _Case.withdrawnEvent:
        await _offer(writer, beacon, helper);
        await _events(writer, a, c, [3]);
      case _Case.missingOffer:
        break;
      case _Case.pending:
      case _Case.userDismissed:
      case _Case.closedRequest:
        await _offer(writer, beacon, helper);
      case _Case.optionalReceipt:
        await _offer(writer, beacon, helper, status: 1);
    }
    await _receipt(
      writer,
      id: _receiptId(a, c),
      accountId: author,
      beaconId: beacon,
      targetEntityId: helper,
      requiresAction: c != _Case.optionalReceipt,
      settlementKind: c == _Case.userDismissed ? 'dismissed' : null,
      settledByUserId: c == _Case.userDismissed ? author : null,
      clearedAt: c == _Case.optionalReceipt ? '2026-09-01T10:00:00Z' : null,
      seenAt: '2026-08-17T09:00:00Z',
    );
  }
}

Future<void> _user(Connection writer, String id) => writer.execute(
  Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, 'key-' || @id)
ON CONFLICT (id) DO NOTHING
'''),
  parameters: {'id': id},
);

Future<void> _offer(
  Connection writer,
  String beaconId,
  String userId, {
  int status = 0,
  String? withdrawReason,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, message, status, offer_kind, stake_state, withdraw_reason)
VALUES (@beaconId, @userId, 'offer', @status, 0, 1, @withdrawReason)
'''),
  parameters: {
    'beaconId': beaconId,
    'userId': userId,
    'status': status,
    'withdrawReason': withdrawReason,
  },
);

/// Records the commitment events in order; each later one gets a higher seq.
Future<void> _events(
  Connection writer,
  String a,
  _Case c,
  List<int> kinds,
) async {
  for (var i = 0; i < kinds.length; i++) {
    final kind = kinds[i];
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_commitment_event
  (id, beacon_id, user_id, actor_user_id, kind)
VALUES (@id, @beaconId, @userId, @actor, @kind)
'''),
      parameters: {
        'id': 'Cstlo$a${c.code}0$i',
        'beaconId': _beacon(a, c),
        'userId': _helper(a, c),
        'actor': (kind == 0 || kind == 3) ? _helper(a, c) : _author(a),
        'kind': kind,
      },
    );
  }
}

int _occurrenceSeq = 0;

Future<void> _receipt(
  Connection writer, {
  required String id,
  required String accountId,
  required String beaconId,
  required String targetEntityId,
  required bool requiresAction,
  String? settlementKind,
  String? settledByUserId,
  String? clearedAt,
  String? seenAt,
}) async {
  const eventType = 'helpOfferSubmitted';
  final sourceEventKey = 'stale-offer:${_occurrenceSeq++}:$id';
  final occurrence = await writer.execute(
    Sql.named('''
INSERT INTO public.attention_occurrence
  (source_event_key, event_type, actor_user_id, immutable_payload)
VALUES (@key, @eventType, NULL, '{"eventType":"fixture"}'::jsonb)
RETURNING id
'''),
    parameters: {'key': sourceEventKey, 'eventType': eventType},
  );
  final occurrenceId = occurrence.single[0]! as String;
  final logicalTaskKey = requiresAction
      ? 'v1|$eventType|$beaconId|$targetEntityId|$accountId'
      : null;
  await writer.execute(
    Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key, occurrence_id, target_entity_id,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key,
  logical_task_key, lifecycle_generation,
  settlement_kind, settled_at, settled_by_user_id,
  cleared_at, clear_reason, seen_at
) VALUES (
  @id, @accountId, 'asksOfMe', 'commitmentEvent', 'normal',
  'Obligation', 'Obligation body', '/attention', @dedupKey,
  '2026-08-16T12:00:00Z'::timestamptz,
  @beaconId, @sourceEventKey, @occurrenceId, CAST(@targetEntityId AS text),
  'beacon', 'help_offer_submitted', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, CAST(@threadKey AS text),
  CAST(@logicalTaskKey AS text), CAST(@generation AS int),
  CAST(@settlementKind AS text),
  CASE WHEN CAST(@settlementKind AS text) IS NULL THEN NULL
       ELSE '2026-08-20T12:00:00Z'::timestamptz END,
  CAST(@settledByUserId AS text),
  CAST(@clearedAt AS timestamptz),
  CASE WHEN CAST(@clearedAt AS timestamptz) IS NULL THEN NULL ELSE 'sweep' END,
  CAST(@seenAt AS timestamptz)
)
'''),
    parameters: {
      'id': id,
      'accountId': accountId,
      'dedupKey': 'dedup-$id',
      'beaconId': beaconId,
      'sourceEventKey': sourceEventKey,
      'occurrenceId': occurrenceId,
      'targetEntityId': targetEntityId,
      'requiresAction': requiresAction,
      'threadKey': requiresAction ? 'v1|$eventType|$beaconId|$accountId' : null,
      'logicalTaskKey': logicalTaskKey,
      'generation': logicalTaskKey == null ? null : 1,
      'settlementKind': settlementKind,
      'settledByUserId': settledByUserId,
      'clearedAt': clearedAt,
      'seenAt': seenAt,
    },
  );
}

// ---------------------------------------------------------------------------
// probes
// ---------------------------------------------------------------------------

const _kindCol = 0;
const _settledAtCol = 1;
const _settledByCol = 2;
const _clearedAtCol = 3;
const _seenAtCol = 4;

/// Every fixture receipt by id: settlement kind, settled_at, settled_by,
/// cleared_at, seen_at, requires_action.
Future<Map<String, List<Object?>>> _rows(Connection writer) async {
  final result = await writer.execute('''
SELECT id, settlement_kind, settled_at, settled_by_user_id,
       cleared_at, seen_at, requires_action
FROM public.notification_outbox
WHERE id LIKE 'Nstlo%'
ORDER BY id
''');
  return {
    for (final row in result) row[0]! as String: row.sublist(1),
  };
}
