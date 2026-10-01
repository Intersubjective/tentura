@Tags(['pg'])
library;

import 'dart:math';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/closure/closure_exception.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/recording_beacon_hierarchy_outbox.dart';

/// A14: `ClosureFinalizeCase` / `ClosureFinalizeSweepCase` (Arch §5.9).
///
/// Runs without the pgmer2 extension, so any MeritRank call made while
/// finalizing would fail the test ("no MR call").
///
/// Collaborator wiring lives in [buildFinalizer] / [buildSweep] below; the
/// behaviour is asserted through the database only.

const _author = 'Uclfinauth001';
const _u1 = 'Uclfinuser001';
const _u2 = 'Uclfinuser002';
const _u3 = 'Uclfinuser003';
const _u4 = 'Uclfinuser004';
const _beacon = 'Bclfinbeac001';
const _users = [_author, _u1, _u2, _u3, _u4];

// trust_kind_config.kind
const _kHelped = 2;
const _kMarked = 3;
const _kWorkedWithAuthor = 8;
const _kSupportedColleague = 9;

const _done = 1;
const _notDone = 2;
const _cantJudge = 3;

const _voluntary = 1;
const _removed = 2;

// beacon_closure_result.band
const _bandRaised = 1;
const _bandAsIfSilent = 2;
const _bandLowered = 3;

// beacon_closure_result.draft_flag
const _flagNone = 0;
const _flagNotCounted = 1;
const _flagLastEditNotCounted = 2;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_FINALIZE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_finalize',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late ClosureRepository repo;
  late MutatingUnitOfWork uow;
  late RecordingBeaconHierarchyOutbox outbox;
  late TrustPublisherCase publisher;
  late ClosureFinalizeCase finalizer;
  late ClosureFinalizeSweepCase sweep;

  ClosureFinalizeCase buildFinalizer() => ClosureFinalizeCase(
    unitOfWork: uow,
    closureRepository: repo,
    beaconRepository: BeaconRepository(db),
    trustLedger: TrustLedgerRepository(db),
    lifecycleEffects: buildLifecycleEffectsCase(outbox: outbox),
    attentionSystemSettlement: AttentionSystemSettlementRepository(db),
    trustPublisher: publisher,
    env: Env(environment: Environment.test),
    logger: Logger('ClosureFinalizePgTest'),
  );

  ClosureFinalizeSweepCase buildSweep() => ClosureFinalizeSweepCase(
    unitOfWork: uow,
    closureRepository: repo,
    finalizer: finalizer,
    env: Env(environment: Environment.test),
    logger: Logger('ClosureFinalizeSweepPgTest'),
  );

  ClosureCase buildClosureCase() => ClosureCase(
    unitOfWork: uow,
    closureRepository: repo,
    beaconRepository: BeaconRepository(db),
    commitmentRepository: CommitmentRepository(db),
    helpOfferRepository: HelpOfferRepository(db),
    hierarchyRepository: FakeBeaconHierarchyRepository(),
    lifecycleEffects: buildLifecycleEffectsCase(outbox: outbox),
    attentionSystemSettlement: AttentionSystemSettlementRepository(db),
    receipts: NoopClosureReceipts(),
    finalizer: finalizer,
    env: Env(environment: Environment.test),
    logger: Logger('ClosureFinalizePgTestClosureCase'),
  );

  Future<void> sql(String s) => writer.execute(s);

  Future<List<List<Object?>>> rows(String s) async =>
      (await writer.execute(s)).map((r) => r.toList()).toList();

  Future<void> seedEpoch({
    int epoch = 1,
    int status = 0,
    String closesAt = "now() - interval '1 hour'",
  }) => sql('''
INSERT INTO public.beacon_closure (beacon_id, epoch, status, opened_at, closes_at)
VALUES ('$_beacon', $epoch, $status, now() - interval '8 days', $closesAt)
''');

  Future<void> member(
    String id, {
    int epoch = 1,
    bool activeAtOpen = true,
    int? departure,
    int? outcome = _done,
  }) async {
    await sql('''
INSERT INTO public.beacon_closure_member
  (beacon_id, epoch, user_id, departure, active_at_open)
VALUES ('$_beacon', $epoch, '$id', ${departure ?? 'NULL'}, $activeAtOpen)
''');
    if (outcome != null) {
      await sql('''
INSERT INTO public.beacon_closure_outcome (beacon_id, helper_id, outcome)
VALUES ('$_beacon', '$id', $outcome)
''');
    }
  }

  Future<void> split(Map<String, int> pct) async {
    for (final e in pct.entries) {
      await sql('''
INSERT INTO public.beacon_closure_author_split (beacon_id, helper_id, pct)
VALUES ('$_beacon', '${e.key}', ${e.value})
''');
    }
  }

  Future<void> support(
    String voter,
    Iterable<String> targets, {
    required int version,
  }) async {
    for (final t in targets) {
      await sql('''
INSERT INTO public.beacon_closure_support (beacon_id, voter_id, target_id, version)
VALUES ('$_beacon', '$voter', '$t', $version)
''');
    }
  }

  Future<void> commit(String voter) => sql('''
INSERT INTO public.beacon_closure_commit (beacon_id, voter_id, committed_at)
VALUES ('$_beacon', '$voter', now())
''');

  /// Draft + commit of the same set (what `done` produces).
  Future<void> committedSupport(String voter, Iterable<String> targets) async {
    await support(voter, targets, version: 0);
    await support(voter, targets, version: 1);
    await commit(voter);
  }

  Future<int> evidenceCount(int kind, {String? subject, String? object}) async {
    final r = await rows('''
SELECT count(*)::int FROM public.trust_evidence
WHERE beacon_id = '$_beacon' AND kind = $kind
  ${subject == null ? '' : "AND subject_user_id = '$subject'"}
  ${object == null ? '' : "AND object_user_id = '$object'"}
''');
    return r.single.single! as int;
  }

  Future<double?> evidenceCountValue(
    int kind,
    String subject,
    String object,
  ) async {
    final r = await rows('''
SELECT count FROM public.trust_evidence
WHERE beacon_id = '$_beacon' AND kind = $kind
  AND subject_user_id = '$subject' AND object_user_id = '$object'
''');
    return r.isEmpty ? null : r.single.single! as double;
  }

  Future<int> allEvidenceCount() async {
    final r = await rows(
      "SELECT count(*)::int FROM public.trust_evidence WHERE beacon_id = '$_beacon'",
    );
    return r.single.single! as int;
  }

  Future<List<List<Object?>>> results() => rows('''
SELECT user_id, outcome, band, draft_flag, helped
FROM public.beacon_closure_result
WHERE beacon_id = '$_beacon' ORDER BY user_id
''');

  Future<Map<String, Object?>> resultOf(String id) async {
    final r = await rows('''
SELECT outcome, band, draft_flag, helped FROM public.beacon_closure_result
WHERE beacon_id = '$_beacon' AND user_id = '$id'
''');
    expect(r, hasLength(1), reason: 'one result row for $id');
    return {
      'outcome': r.single[0],
      'band': r.single[1],
      'flag': r.single[2],
      'helped': r.single[3],
    };
  }

  Future<int> epochStatus(int epoch) async {
    final r = await rows('''
SELECT status FROM public.beacon_closure
WHERE beacon_id = '$_beacon' AND epoch = $epoch
''');
    return r.single.single! as int;
  }

  Future<int> beaconStatus() async {
    final r = await rows(
      "SELECT status FROM public.beacon WHERE id = '$_beacon'",
    );
    return r.single.single! as int;
  }

  Future<void> finalizeNow({
    int epoch = 1,
    FinalizeReason reason = FinalizeReason.expired,
  }) => uow.run(
    actorUserId: _author,
    action: () => finalizer.finalize(
      beaconId: _beacon,
      epoch: epoch,
      reason: reason,
    ),
  );

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      db = TenturaDb(target.databaseEnv);
      repo = ClosureRepository(db);
      uow = MutatingUnitOfWork(db);
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      await sql('''
TRUNCATE public.beacon_closure_result, public.beacon_closure_member,
  public.beacon_closure, public.beacon_closure_outcome,
  public.beacon_closure_author_split, public.beacon_closure_support,
  public.beacon_closure_commit, public.beacon_closure_mark,
  public.beacon_closure_story, public.trust_evidence,
  public.trust_publish_queue, public.user_block
CASCADE
''');
      await sql('DELETE FROM public.user_trust_edge');
      await sql("DELETE FROM public.beacon WHERE id = 'Bclfinchild01'");
      await sql("DELETE FROM public.beacon WHERE id = '$_beacon'");
      await sql(
        "UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1",
      );
      for (var i = 0; i < _users.length; i++) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${_users[i]}', '${_users[i]}', '${pgTestPublicKey('clfin', i + 1)}')
ON CONFLICT (id) DO NOTHING
''');
      }
      await sql('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_beacon', '$_author', 'closure finalize test', '',
        ${BeaconStatus.reviewOpen.smallintValue}, now())
''');
      outbox = RecordingBeaconHierarchyOutbox();
      publisher = TrustPublisherCase(
        TrustPublishRepository(db),
        env: Env(environment: Environment.test),
        logger: Logger('ClosureFinalizePgTestPublisher'),
      );
      finalizer = buildFinalizer();
      sweep = buildSweep();
    });
  }

  group('ClosureFinalizeCase', () {
    test(
      'V3 bands, helped evidence counts, queue rows, epoch and beacon final',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await split({_u1: 70, _u2: 20, _u3: 10});
        await committedSupport(_u1, [_u3]);

        await finalizeNow(reason: FinalizeReason.authorCloseNow);

        expect(await epochStatus(1), 1);
        final epochRow = await rows('''
SELECT finalized_at IS NOT NULL, finalize_reason, settlement_version,
       settlement_params IS NOT NULL
FROM public.beacon_closure WHERE beacon_id = '$_beacon' AND epoch = 1
''');
        expect(epochRow.single, [true, 1, 1, true]);
        expect(await beaconStatus(), BeaconStatus.closed.smallintValue);

        final r1 = await resultOf(_u1);
        final r2 = await resultOf(_u2);
        final r3 = await resultOf(_u3);
        expect(r1['band'], _bandAsIfSilent);
        expect(r2['band'], _bandLowered);
        expect(r3['band'], _bandRaised);
        expect(r1['helped'] as double, closeTo(0.3856, 5e-4));
        expect(r2['helped'] as double, closeTo(0.1471, 5e-4));
        expect(r3['helped'] as double, closeTo(0.1672, 5e-4));

        expect(
          await evidenceCountValue(_kHelped, _author, _u1),
          closeTo(0.3856, 5e-4),
        );
        expect(
          await evidenceCountValue(_kHelped, _author, _u2),
          closeTo(0.1471, 5e-4),
        );
        expect(
          await evidenceCountValue(_kHelped, _author, _u3),
          closeTo(0.1672, 5e-4),
        );
        final keys = await rows('''
SELECT source_key FROM public.trust_evidence
WHERE beacon_id = '$_beacon' AND kind = $_kHelped ORDER BY source_key
''');
        expect(keys.map((r) => r.single), [
          'closure:$_beacon:1:helped:$_u1',
          'closure:$_beacon:1:helped:$_u2',
          'closure:$_beacon:1:helped:$_u3',
        ]);

        for (final u in [_u1, _u2, _u3]) {
          final q = await rows('''
SELECT count(*)::int FROM public.trust_publish_queue
WHERE subject_user_id = '$_author' AND object_user_id = '$u'
''');
          expect(q.single.single, 1, reason: 'queue row author->$u');
        }
        // Published edges of the other kinds are queued too: U58 helper ->
        // author for every member, U59 u1 -> u3 (routed edges need forward
        // edges and are not covered here).
        for (final u in [_u1, _u2, _u3]) {
          final q = await rows('''
SELECT count(*)::int FROM public.trust_publish_queue
WHERE subject_user_id = '$u' AND object_user_id = '$_author'
''');
          expect(q.single.single, 1, reason: 'queue row $u->author (U58)');
        }
        final q59 = await rows('''
SELECT count(*)::int FROM public.trust_publish_queue
WHERE subject_user_id = '$_u1' AND object_user_id = '$_u3'
''');
        expect(q59.single.single, 1, reason: 'queue row u1->u3 (U59)');
      },
      skip: skipReason,
    );

    test(
      'draft flags: notCounted, lastEditNotCounted, none',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        // u1: draft only, never pressed Done.
        await support(_u1, [_u3], version: 0);
        // u2: committed {u3}, then edited the draft to {u1, u3}.
        await support(_u2, [_u3], version: 1);
        await support(_u2, [_u1, _u3], version: 0);
        await commit(_u2);
        // u3: draft == committed.
        await committedSupport(_u3, [_u1]);

        await finalizeNow();

        expect((await resultOf(_u1))['flag'], _flagNotCounted);
        expect((await resultOf(_u2))['flag'], _flagLastEditNotCounted);
        expect((await resultOf(_u3))['flag'], _flagNone);
      },
      skip: skipReason,
    );

    test(
      'draft-only voter is notCounted and does not change shares',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await support(_u1, [_u3], version: 0);
        await finalizeNow();
        final withDraft = {
          for (final u in [_u1, _u2, _u3]) u: (await resultOf(u))['helped'],
        };
        expect((await resultOf(_u1))['flag'], _flagNotCounted);

        // Same episode without any draft: identical shares.
        await sql('TRUNCATE public.beacon_closure CASCADE');
        await sql('TRUNCATE public.beacon_closure_support');
        await sql('DELETE FROM public.trust_evidence');
        await sql(
          "UPDATE public.beacon SET status = ${BeaconStatus.reviewOpen.smallintValue} WHERE id = '$_beacon'",
        );
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u, outcome: null);
          await sql('''
INSERT INTO public.beacon_closure_outcome (beacon_id, helper_id, outcome)
VALUES ('$_beacon', '$u', $_done) ON CONFLICT DO NOTHING
''');
        }
        await finalizeNow();
        for (final u in [_u1, _u2, _u3]) {
          expect((await resultOf(u))['helped'], withDraft[u]);
        }
      },
      skip: skipReason,
    );

    test(
      'null outcome is stored as 3 (cantJudge)',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2, outcome: null);
        await finalizeNow();
        expect((await resultOf(_u2))['outcome'], _cantJudge);
      },
      skip: skipReason,
    );

    test(
      'finalizing the same epoch twice: second call is a no-op',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await finalizeNow();
        final before = await results();
        final evidence = await allEvidenceCount();
        final finalizedAt = await rows('''
SELECT finalized_at FROM public.beacon_closure WHERE beacon_id = '$_beacon'
''');

        await finalizeNow();

        expect(await results(), before);
        expect(await allEvidenceCount(), evidence);
        expect(
          await rows('''
SELECT finalized_at FROM public.beacon_closure WHERE beacon_id = '$_beacon'
'''),
          finalizedAt,
        );
      },
      skip: skipReason,
    );

    test(
      'expired finalize before closes_at is a no-op',
      () async {
        await seedEpoch(closesAt: "now() + interval '1 day'");
        await member(_u1);
        await finalizeNow();
        expect(await epochStatus(1), 0);
        expect(await results(), isEmpty);
        expect(await beaconStatus(), BeaconStatus.reviewOpen.smallintValue);
      },
      skip: skipReason,
    );

    test(
      'cancelled epoch finalize is a no-op (no results, no evidence)',
      () async {
        await seedEpoch(status: 2);
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await committedSupport(_u1, [_u2]);
        await finalizeNow();
        expect(await epochStatus(1), 2);
        expect(await results(), isEmpty);
        expect(await allEvidenceCount(), 0);
      },
      skip: skipReason,
    );

    test(
      'marks become marked evidence at finalized_at',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2);
        await sql('''
INSERT INTO public.beacon_closure_mark (beacon_id, marker_id, target_id)
VALUES ('$_beacon', '$_u1', '$_u2')
''');
        await finalizeNow();
        expect(await evidenceCount(_kMarked, subject: _u1, object: _u2), 1);
        final key = await rows('''
SELECT source_key, occurred_at = (
  SELECT finalized_at FROM public.beacon_closure WHERE beacon_id = '$_beacon'
) FROM public.trust_evidence
WHERE beacon_id = '$_beacon' AND kind = $_kMarked
''');
        expect(key.single, ['closure:$_beacon:1:mark:$_u1:$_u2', true]);
      },
      skip: skipReason,
    );

    test(
      'story becomes a room system message of kind 3',
      () async {
        await seedEpoch();
        await member(_u1);
        await sql('''
INSERT INTO public.beacon_closure_story (beacon_id, body)
VALUES ('$_beacon', 'We did it.')
''');
        await finalizeNow();
        final r = await rows('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE beacon_id = '$_beacon' AND system_message_kind = 3
''');
        expect(r.single.single, 1);
      },
      skip: skipReason,
    );

    test(
      'close effects recorded: status transition, hierarchy events for the '
      'request and its child, pending-offer obligation superseded',
      () async {
        await seedEpoch();
        await member(_u1);
        // A pending (never accepted) offer with a live author obligation.
        await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status)
VALUES ('$_beacon', '$_u4', 0)
''');
        await sql('''
INSERT INTO public.attention_occurrence
  (id, source_event_key, event_type, actor_user_id, immutable_payload)
VALUES ('Oclfinocc001', 'clfin:offer:1', 'helpOfferSubmitted', '$_u4', '{}')
''');
        await sql('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, beacon_id, title, body, action_url,
  priority, dedup_key, source_event_key, destination_kind, presentation_key,
  access_policy, requires_action, attention_thread_key, occurrence_id)
VALUES ('Nclfinout001', '$_author', 'beacon', 'helpOfferSubmitted',
  '$_beacon', 't', 'b', '/', 'normal', 'clfin:dedup:1', 'clfin:offer:1',
  'beacon', 'help_offer_submitted', 'beacon_content', true,
  'v1|a|b|c', 'Oclfinocc001')
''');
        // A child request of the closing one.
        await sql('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, parent_beacon_id)
VALUES ('Bclfinchild01', '$_author', 'child', '',
        ${BeaconStatus.open.smallintValue}, now(), '$_beacon')
''');

        // `unansweredAtClose` was recorded when the epoch opened; finalize
        // must keep it (exactly one) and not add another.
        await uow.run(
          actorUserId: _author,
          action: () => CommitmentRepository(db).record(
            beaconId: _beacon,
            userId: _u4,
            actorUserId: _author,
            kind: CommitmentEventKind.unansweredAtClose,
          ),
        );

        await finalizeNow();

        expect(
          (await rows('''
SELECT count(*)::int FROM public.beacon_commitment_event
WHERE beacon_id = '$_beacon' AND user_id = '$_u4'
  AND kind = ${CommitmentEventKind.unansweredAtClose.smallintValue}
''')).single.single,
          1,
        );
        expect(await beaconStatus(), BeaconStatus.closed.smallintValue);
        final fromParent = outbox.recordedEvents.where(
          (e) => e.sourceBeaconId == _beacon,
        );
        expect(fromParent, hasLength(1));
        expect(fromParent.single.fromStatus, BeaconStatus.reviewOpen);
        expect(fromParent.single.toStatus, BeaconStatus.closed);
        expect(
          outbox.topologyInserts.map((e) => e.sourceBeaconId),
          contains(_beacon),
        );
        final settled = await rows('''
SELECT settlement_kind FROM public.notification_outbox WHERE id = 'Nclfinout001'
''');
        expect(settled.single.single, 'superseded');
        // The child is not closed by its parent's finalize.
        expect(
          (await rows(
            "SELECT status FROM public.beacon WHERE id = 'Bclfinchild01'",
          )).single.single,
          BeaconStatus.open.smallintValue,
        );
      },
      skip: skipReason,
    );

    test(
      'close-acks: Done members get capability close-acknowledgement events '
      'over the offer help type, notDone members none',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2, outcome: _notDone);
        for (final u in [_u1, _u2]) {
          await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status, help_type)
VALUES ('$_beacon', '$u', 1, 'plumbing')
''');
        }
        await finalizeNow();
        Future<int> acks(String u) async => (await rows('''
SELECT count(*)::int FROM public.person_capability_event
WHERE beacon_id = '$_beacon' AND source_type = 3 AND tag_slug = 'plumbing'
  AND deleted_at IS NULL AND (subject_user_id = '$u' OR observer_user_id = '$u')
''')).single.single! as int;
        expect(await acks(_u1), greaterThan(0));
        expect(await acks(_u2), 0);
      },
      skip: skipReason,
    );

    test(
      'user deleted after finalize: others keep results, own trust rows go, '
      'published edges are queued',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await finalizeNow();
        final othersBefore = await rows('''
SELECT user_id, outcome, band, draft_flag, helped
FROM public.beacon_closure_result
WHERE beacon_id = '$_beacon' AND user_id <> '$_u2' ORDER BY user_id
''');
        await sql(
          'UPDATE public.user_trust_edge SET prev_sent_weight = target_w',
        );
        await sql('DELETE FROM public.trust_publish_queue');

        await sql('''DELETE FROM public."user" WHERE id = '$_u2' ''');

        expect(
          await rows('''
SELECT user_id, outcome, band, draft_flag, helped
FROM public.beacon_closure_result
WHERE beacon_id = '$_beacon' ORDER BY user_id
'''),
          othersBefore,
        );
        final gone = await rows('''
SELECT count(*)::int FROM public.trust_evidence
WHERE subject_user_id = '$_u2' OR object_user_id = '$_u2'
''');
        expect(gone.single.single, 0);
        final edges = await rows('''
SELECT count(*)::int FROM public.user_trust_edge
WHERE subject = '$_u2' OR object = '$_u2'
''');
        expect(edges.single.single, 0);
        final queued = await rows('''
SELECT count(*)::int FROM public.trust_publish_queue
WHERE subject_user_id = '$_author' AND object_user_id = '$_u2'
''');
        expect(queued.single.single, 1);
      },
      skip: skipReason,
    );
  });

  group('U58 worked_with_author', () {
    test(
      'three present members: three rows helper->author, 1/sqrt(3); '
      'notDone member included',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2, outcome: _notDone);
        await member(_u3);
        await finalizeNow();
        for (final u in [_u1, _u2, _u3]) {
          expect(
            await evidenceCountValue(_kWorkedWithAuthor, u, _author),
            closeTo(1 / sqrt(3), 1e-9),
            reason: '$u -> author',
          );
        }
        expect(await evidenceCount(_kWorkedWithAuthor), 3);
        final key = await rows('''
SELECT source_key, occurred_at = (
  SELECT finalized_at FROM public.beacon_closure WHERE beacon_id = '$_beacon'
) FROM public.trust_evidence
WHERE beacon_id = '$_beacon' AND kind = $_kWorkedWithAuthor
  AND subject_user_id = '$_u1'
''');
        expect(key.single, ['closure:$_beacon:1:author_edge:$_u1', true]);
      },
      skip: skipReason,
    );

    test(
      'withdrawn and removed members get none and P shrinks',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2);
        await member(_u3, departure: _voluntary);
        await member(_u4, departure: _removed, activeAtOpen: true);
        await finalizeNow();
        expect(await evidenceCount(_kWorkedWithAuthor), 2);
        expect(await evidenceCount(_kWorkedWithAuthor, subject: _u3), 0);
        expect(await evidenceCount(_kWorkedWithAuthor, subject: _u4), 0);
        for (final u in [_u1, _u2]) {
          expect(
            await evidenceCountValue(_kWorkedWithAuthor, u, _author),
            closeTo(1 / sqrt(2), 1e-9),
          );
        }
      },
      skip: skipReason,
    );

    test(
      'single member: count 1',
      () async {
        await seedEpoch();
        await member(_u1);
        await finalizeNow();
        expect(await evidenceCountValue(_kWorkedWithAuthor, _u1, _author), 1);
      },
      skip: skipReason,
    );

    test(
      'cancelled epoch writes none',
      () async {
        await seedEpoch(status: 2);
        await member(_u1);
        await finalizeNow();
        expect(await evidenceCount(_kWorkedWithAuthor), 0);
      },
      skip: skipReason,
    );

    test(
      'blocked pair: evidence row exists, published wall -1, trust_recent 0',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2);
        await sql('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_u1', '$_author', '$_u1')
''');
        await finalizeNow();
        expect(await evidenceCount(_kWorkedWithAuthor, subject: _u1), 1);
        final edge = await rows('''
SELECT coalesce(max(target_w), 0) FROM public.user_trust_edge
WHERE subject = '$_u1' AND object = '$_author'
''');
        expect(edge.single.single, -1);
        final fold = await rows(
          "SELECT trust_recent FROM public.trust_fold_pair('$_u1', '$_author')",
        );
        expect(fold.single.single, 0);
      },
      skip: skipReason,
    );
    test(
      'reopening an evaluating epoch writes no worked_with_author',
      () async {
        await seedEpoch(closesAt: "now() + interval '3 days'");
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await committedSupport(_u1, [_u2]);
        await buildClosureCase().reopen(
          authorId: _author,
          beaconId: _beacon,
          expectedEpoch: 1,
        );
        expect(await epochStatus(1), 2);
        // A stale finalize of the cancelled epoch must not write either.
        await finalizeNow();
        expect(await evidenceCount(_kWorkedWithAuthor), 0);
        expect(await results(), isEmpty);
      },
      skip: skipReason,
    );

  });

  group('U59 supported_colleague', () {
    test(
      'four members, u1 supports {u2,u3}: two rows with 1/sqrt(2)',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3, _u4]) {
          await member(u);
        }
        await committedSupport(_u1, [_u2, _u3]);
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague), 2);
        for (final t in [_u2, _u3]) {
          expect(
            await evidenceCountValue(_kSupportedColleague, _u1, t),
            closeTo(1 / sqrt(2), 1e-9),
          );
        }
        final key = await rows('''
SELECT source_key, occurred_at = (
  SELECT finalized_at FROM public.beacon_closure WHERE beacon_id = '$_beacon'
) FROM public.trust_evidence
WHERE beacon_id = '$_beacon' AND kind = $_kSupportedColleague
  AND object_user_id = '$_u2'
''');
        expect(key.single, ['closure:$_beacon:1:support_edge:$_u1:$_u2', true]);
      },
      skip: skipReason,
    );

    test(
      'V20 (u2 notDone, u1 supports u3, zero bonus) still writes u1->u3, count 1',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2, outcome: _notDone);
        await member(_u3);
        await split({_u1: 30, _u3: 70});
        await committedSupport(_u1, [_u3]);
        await finalizeNow();
        expect((await resultOf(_u1))['band'], _bandAsIfSilent);
        expect((await resultOf(_u3))['band'], _bandAsIfSilent);
        expect(
          await evidenceCountValue(_kSupportedColleague, _u1, _u3),
          closeTo(1, 1e-9),
        );
      },
      skip: skipReason,
    );

    test(
      'support of a notDone or a withdrawn member writes the row',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2, outcome: _notDone);
        await member(_u3);
        await member(_u4, departure: _voluntary);
        await committedSupport(_u1, [_u2, _u4]);
        await finalizeNow();
        expect(
          await evidenceCountValue(_kSupportedColleague, _u1, _u2),
          closeTo(1 / sqrt(2), 1e-9),
        );
        expect(
          await evidenceCountValue(_kSupportedColleague, _u1, _u4),
          closeTo(1 / sqrt(2), 1e-9),
        );
      },
      skip: skipReason,
    );

    test(
      'none for a draft without Done',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await support(_u1, [_u2], version: 0);
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague), 0);
      },
      skip: skipReason,
    );

    test(
      'none for a non-voter (removed member) even with committed rows',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2);
        await member(_u3, departure: _removed);
        await committedSupport(_u3, [_u1]);
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague, subject: _u3), 0);
      },
      skip: skipReason,
    );

    test(
      'none for 2-member requests',
      () async {
        await seedEpoch();
        await member(_u1);
        await member(_u2);
        await committedSupport(_u1, [_u2]);
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague), 0);
      },
      skip: skipReason,
    );

    test(
      'none for a cancelled epoch',
      () async {
        await seedEpoch(status: 2);
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await committedSupport(_u1, [_u2]);
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague), 0);
      },
      skip: skipReason,
    );

    test(
      'support covering every other member is silence (U56): no rows, settled as silence',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await committedSupport(_u1, [_u2, _u3]);
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague), 0);
        expect((await resultOf(_u1))['flag'], _flagNone);
        // Settlement treats it as silence: no one is raised or lowered and
        // the equal shares stay equal.
        for (final u in [_u1, _u2, _u3]) {
          expect((await resultOf(u))['band'], _bandAsIfSilent, reason: u);
        }
        final h = [
          for (final u in [_u1, _u2, _u3])
            (await resultOf(u))['helped']! as double,
        ];
        expect(h[1], closeTo(h[0], 1e-9));
        expect(h[2], closeTo(h[0], 1e-9));
      },
      skip: skipReason,
    );

    test(
      'commit without any support rows writes none',
      () async {
        await seedEpoch();
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await commit(_u1);
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague), 0);
      },
      skip: skipReason,
    );
    test(
      'reopening an evaluating epoch writes no supported_colleague',
      () async {
        await seedEpoch(closesAt: "now() + interval '3 days'");
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await committedSupport(_u1, [_u2]);
        await buildClosureCase().reopen(
          authorId: _author,
          beaconId: _beacon,
          expectedEpoch: 1,
        );
        expect(await epochStatus(1), 2);
        // A stale finalize of the cancelled epoch must not write either.
        await finalizeNow();
        expect(await evidenceCount(_kSupportedColleague), 0);
        expect(await results(), isEmpty);
      },
      skip: skipReason,
    );

  });

  group('ClosureFinalizeSweepCase', () {
    test(
      'finalizes due epochs only',
      () async {
        await seedEpoch();
        await member(_u1);
        await sweep.run();
        expect(await epochStatus(1), 1);
        expect(await beaconStatus(), BeaconStatus.closed.smallintValue);
        expect(
          (await rows('''
SELECT finalize_reason FROM public.beacon_closure WHERE beacon_id = '$_beacon'
''')).single.single,
          FinalizeReason.expired.dbValue,
        );
      },
      skip: skipReason,
    );

    test(
      'not-yet-due epoch is left alone',
      () async {
        await seedEpoch(closesAt: "now() + interval '1 day'");
        await member(_u1);
        await sweep.run();
        expect(await epochStatus(1), 0);
      },
      skip: skipReason,
    );

    test(
      'author extends between select and lock: no-op',
      () async {
        await seedEpoch();
        await member(_u1);
        sweep.afterSelect = () => sql('''
UPDATE public.beacon_closure
SET closes_at = now() + interval '7 days', extensions_used = 1
WHERE beacon_id = '$_beacon' AND epoch = 1
''');
        await sweep.run();
        expect(await epochStatus(1), 0);
        expect(await results(), isEmpty);
        expect(await beaconStatus(), BeaconStatus.reviewOpen.smallintValue);
      },
      skip: skipReason,
    );

    test(
      'reopen + reclose between select and lock: the new epoch is untouched',
      () async {
        await seedEpoch();
        await member(_u1);
        sweep.afterSelect = () async {
          await sql('''
UPDATE public.beacon_closure SET status = 2
WHERE beacon_id = '$_beacon' AND epoch = 1
''');
          await seedEpoch(epoch: 2, closesAt: "now() + interval '7 days'");
          await member(_u1, epoch: 2, outcome: null);
        };
        await sweep.run();
        expect(await epochStatus(1), 2);
        expect(await epochStatus(2), 0);
        expect(await results(), isEmpty);
        expect(await beaconStatus(), BeaconStatus.reviewOpen.smallintValue);
      },
      skip: skipReason,
    );

    test(
      'one failing row is isolated: later rows still finalize',
      () async {
        // Beacon 002 is due first and its finalize is forced to fail.
        await sql('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('Bclfinbeac002', '$_author', 'second', '',
        ${BeaconStatus.reviewOpen.smallintValue}, now())
''');
        await sql('''
INSERT INTO public.beacon_closure (beacon_id, epoch, status, opened_at, closes_at)
VALUES ('Bclfinbeac002', 1, 0, now() - interval '9 days', now() - interval '2 hours')
''');
        await sql('''
INSERT INTO public.beacon_closure_member (beacon_id, epoch, user_id, active_at_open)
VALUES ('Bclfinbeac002', 1, '$_u2', true)
''');
        await sql(r'''
CREATE FUNCTION public.clfin_fail() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'forced finalize failure'; END $$
''');
        await sql('''
CREATE TRIGGER clfin_fail BEFORE INSERT ON public.beacon_closure_result
FOR EACH ROW WHEN (NEW.beacon_id = 'Bclfinbeac002')
EXECUTE FUNCTION public.clfin_fail()
''');
        addTearDown(() async {
          await sql('DROP TRIGGER IF EXISTS clfin_fail ON public.beacon_closure_result');
          await sql('DROP FUNCTION IF EXISTS public.clfin_fail()');
          await sql("DELETE FROM public.beacon WHERE id = 'Bclfinbeac002'");
        });
        await seedEpoch();
        await member(_u1);

        await sweep.run(); // must not throw

        expect(await epochStatus(1), 1, reason: 'healthy row finalized');
        final failed = await rows('''
SELECT status FROM public.beacon_closure WHERE beacon_id = 'Bclfinbeac002'
''');
        expect(failed.single.single, 0, reason: 'failed row rolled back');
        expect(
          (await rows(
            "SELECT status FROM public.beacon WHERE id = 'Bclfinbeac002'",
          )).single.single,
          BeaconStatus.reviewOpen.smallintValue,
        );
      },
      skip: skipReason,
    );
  });

  group('Done vs finalize ordering', () {
    test(
      'Done first: both succeed and the committed support is used',
      () async {
        await seedEpoch(closesAt: "now() + interval '1 day'");
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await split({_u1: 70, _u2: 20, _u3: 10});
        await support(_u1, [_u3], version: 0);
        final closure = buildClosureCase();
        await closure.done(voterId: _u1, beaconId: _beacon, expectedEpoch: 1);
        expect(
          (await rows('''
SELECT count(*)::int FROM public.beacon_closure_support
WHERE beacon_id = '$_beacon' AND voter_id = '$_u1' AND version = 1
''')).single.single,
          1,
        );
        await finalizeNow(reason: FinalizeReason.authorCloseNow);
        expect((await resultOf(_u1))['flag'], _flagNone);
        expect(
          await evidenceCountValue(_kSupportedColleague, _u1, _u3),
          closeTo(1, 1e-9),
        );
        expect((await resultOf(_u3))['band'], _bandRaised);
      },
      skip: skipReason,
    );

    test(
      'finalize first: Done fails with wrongStatus or staleEpoch',
      () async {
        await seedEpoch(closesAt: "now() + interval '1 day'");
        for (final u in [_u1, _u2, _u3]) {
          await member(u);
        }
        await support(_u1, [_u3], version: 0);
        await finalizeNow(reason: FinalizeReason.authorCloseNow);
        final closure = buildClosureCase();
        await expectLater(
          closure.done(voterId: _u1, beaconId: _beacon, expectedEpoch: 1),
          throwsA(
            isA<ClosureException>().having(
              (e) => e.closureCode,
              'closureCode',
              anyOf(
                ClosureExceptionCode.wrongStatus,
                ClosureExceptionCode.staleEpoch,
              ),
            ),
          ),
        );
        expect((await resultOf(_u1))['flag'], _flagNotCounted);
        expect(await evidenceCount(_kSupportedColleague), 0);
      },
      skip: skipReason,
    );
  });
}
