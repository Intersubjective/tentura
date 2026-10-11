@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Budding C7 (Arch §7, I9): closure routing for helpers admitted through an
/// accepted Post invite.
///
/// The Post `_post` (author `_a`) carries A→B→C (`Fc7p1`, `Fc7p2`) and an
/// unrelated A→D→C (`Fc7p3`, `Fc7p4`). The child `_child` was budded by
/// `_a` (or `_b`) five days ago; C was invited (delivery `Fc7d1`) with Post
/// arrival `Fc7p2` and accepted. C may forward the child onward to E.
const _a = 'Uc7a00000001';
const _b = 'Uc7b00000001';
const _c = 'Uc7c00000001';
const _d = 'Uc7d00000001';
const _e = 'Uc7e00000001';
const _users = [_a, _b, _c, _d, _e];

const _post = 'Bc7post00001';
const _child = 'Bc7child0001';

const _kRouted = 4;
const _done = 1;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_ROUTE_CREDIT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_bud_route_credit',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('closure routing across the Post (C7)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = openDisposablePgDatabase(target);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    Future<void> sql(String s) => writer.execute(s);

    Future<void> finalize({bool budRouteCredit = true}) {
      final env = Env(
        environment: Environment.test,
        trustBudRouteCreditEnabled: budRouteCredit,
      );
      final uow = MutatingUnitOfWork(db);
      final finalizer = ClosureFinalizeCase(
        unitOfWork: uow,
        closureRepository: ClosureRepository(db),
        beaconRepository: BeaconRepository(db),
        trustLedger: TrustLedgerRepository(db),
        lifecycleEffects: buildLifecycleEffectsCase(),
        attentionSystemSettlement: AttentionSystemSettlementRepository(db),
        trustPublisher: TrustPublisherCase(
          TrustPublishRepository(db),
          env: env,
          logger: Logger('PostBudRouteCreditPublisher'),
        ),
        env: env,
        logger: Logger('PostBudRouteCreditPgTest'),
      );
      return uow.run(
        actorUserId: _a,
        action: () => finalizer.finalize(
          beaconId: _child,
          epoch: 1,
          reason: FinalizeReason.expired,
        ),
      );
    }

    Future<Set<(String, String)>> routed() async {
      final rows = await writer.execute('''
SELECT subject_user_id, object_user_id FROM public.trust_evidence
WHERE beacon_id = '$_child' AND kind = $_kRouted
''');
      return {for (final r in rows) (r[0]! as String, r[1]! as String)};
    }

    /// Seeds the Post, the child (author [childAuthor]), C's accepted invite
    /// (source [sourcePost], arrival [arrival]) and the closure members.
    Future<void> seed({
      String childAuthor = _a,
      String? sourcePost = _post,
      String? arrival = 'Fc7p2',
      bool onwardToE = false,
      String? cancelP1At,
    }) async {
      await sql('''
TRUNCATE TABLE
  public.trust_evidence,
  public.trust_publish_queue,
  public.beacon_closure_result,
  public.beacon_closure_member,
  public.beacon_closure_outcome,
  public.beacon_closure,
  public.beacon_author_invite,
  public.beacon_help_offer,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
      await sql('DELETE FROM public.user_trust_edge');
      await sql(
        "UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1",
      );
      for (var i = 0; i < _users.length; i++) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${_users[i]}', '${_users[i]}', '${pgTestPublicKey('c7r', i + 1)}')
''');
      }
      await sql('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_a', '', '', 0, 1, 1, false, now() - interval '20 days')
''');
      await sql('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, parent_beacon_id,
   is_discoverable, published_at)
VALUES ('$_child', '$childAuthor', 'Move the piano', '',
        ${BeaconStatus.reviewOpen.smallintValue}, '$_post', false,
        now() - interval '5 days')
''');
      Future<void> edge(
        String id,
        String beacon,
        String sender,
        String recipient,
        String age, {
        String? parent,
        String? cancelledAt,
      }) => sql('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id, batch_id,
   created_at, cancelled_at)
VALUES ('$id', '$beacon', '$sender', '$recipient',
        ${parent == null ? 'NULL' : "'$parent'"}, 'X$id',
        now() - interval '$age',
        ${cancelledAt == null ? 'NULL' : "now() - interval '$cancelledAt'"})
''');
      // The Post: A→B→C and the unrelated A→D→C.
      await edge('Fc7p1', _post, _a, _b, '10 days', cancelledAt: cancelP1At);
      await edge('Fc7p2', _post, _b, _c, '9 days', parent: 'Fc7p1');
      await edge('Fc7p3', _post, _a, _d, '10 days');
      await edge('Fc7p4', _post, _d, _c, '9 days 1 hour', parent: 'Fc7p3');
      // The child: the delivery edge, and C's onward forward to E.
      await edge('Fc7d1', _child, childAuthor, _c, '4 days 23 hours');
      if (onwardToE) {
        await edge('Fc7c1', _child, _c, _e, '4 days', parent: 'Fc7d1');
      }
      await sql('''
INSERT INTO public.beacon_author_invite
  (id, beacon_id, inviter_id, invitee_id, source_post_id, forward_edge_id,
   arrival_post_edge_id, warm, status, resolved_at, resolved_by)
VALUES ('Ic7invite001', '$_child', '$childAuthor', '$_c',
        ${sourcePost == null ? 'NULL' : "'$sourcePost'"}, 'Fc7d1',
        ${arrival == null ? 'NULL' : "'$arrival'"}, true, 1,
        now() - interval '3 days', '$_c')
''');
      final helpers = [_c, if (onwardToE) _e];
      await sql('''
INSERT INTO public.beacon_closure (beacon_id, epoch, status, opened_at, closes_at)
VALUES ('$_child', 1, 0, now() - interval '8 hours', now() - interval '1 hour')
''');
      for (final h in helpers) {
        await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, created_at)
VALUES ('$_child', '$h', now() - interval '3 days')
''');
        await sql('''
INSERT INTO public.beacon_closure_member
  (beacon_id, epoch, user_id, departure, active_at_open)
VALUES ('$_child', 1, '$h', NULL, true)
''');
        await sql('''
INSERT INTO public.beacon_closure_outcome (beacon_id, helper_id, outcome)
VALUES ('$_child', '$h', $_done)
''');
      }
    }

    test('an invitee credits only their Post chain (A→B, B→C)', () async {
      await seed();
      await finalize();
      expect(await routed(), {(_a, _b), (_b, _c)});
    });

    test('a cancelled Post edge on the chain earns nothing', () async {
      await seed(cancelP1At: '6 days');
      await finalize();
      expect(await routed(), isEmpty);
    });

    test('onward forwards route through the delivery root, which earns '
        'nothing (I9)', () async {
      await seed(onwardToE: true);
      await finalize();
      expect(await routed(), {(_a, _b), (_b, _c), (_c, _e)});
    });

    test('a budder in the Post chain earns nothing for the delivery', () async {
      await seed(childAuthor: _b);
      await finalize();
      expect(await routed(), {(_a, _b), (_b, _c)});
    });

    test("a repair invite (no source Post) keeps today's routing", () async {
      await seed(sourcePost: null, arrival: null, onwardToE: true);
      await finalize();
      expect(await routed(), {(_a, _c), (_c, _e)});
    });

    test('kill switch off: no cross-beacon credit', () async {
      await seed(onwardToE: true);
      await finalize(budRouteCredit: false);
      expect(await routed(), {(_a, _c), (_c, _e)});
    });
  });
}
