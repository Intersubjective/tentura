@Tags(['pg', 'mr', 'multi-connection', 'repo-files'])
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'UfhelpAuthor';
const _first = 'UfhelpFirst';
const _second = 'UfhelpSecond';
const _helper = 'UfhelpHelper';
const _otherHelper = 'UfhelpOther';
const _offPath = 'UfhelpOffpath';
const _beacon = 'BfhelpRequest';
const _title = 'Need a van on Saturday';
const _names = {
  _author: 'Anna Author',
  _first: 'Boris First',
  _second: 'Fay Second',
  _helper: 'Vera Helper',
  _otherHelper: 'Nina Helper',
  _offPath: 'Olga Offpath',
};

// Use production DI: new receipt dependencies must be wired into the public
// offer acceptance action, rather than called directly by this test.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_HELPED_CARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_helped_card',
  );
  final skipReason = await pgSkipReason(target);

  group('forward-helped receipts stay on the main Activity Request card', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late HelpOfferCase offers;
    late CoordinationCase coordination;
    late QueryAttention updates;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          maxConnectionCount: testPoolSizeOverride(),
          publicOrigin: 'http://127.0.0.1:2080',
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      offers = getIt<HelpOfferCase>();
      coordination = getIt<CoordinationCase>();
      updates = QueryAttention(query: getIt<AttentionQueryPort>());
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<void> forward(
      String id,
      String sender,
      String recipient, {
      required int hoursAgo,
      String? parent,
      bool cancelled = false,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id,
   created_at, cancelled_at)
VALUES (@id, @beacon, @sender, @recipient, @parent,
  now() - make_interval(hours => @hoursAgo),
  CASE WHEN @cancelled THEN now() - interval '30 minutes' ELSE NULL END)
'''),
      parameters: {
        'id': id,
        'beacon': _beacon,
        'sender': sender,
        'recipient': recipient,
        'parent': parent,
        'hoursAgo': hoursAgo,
        'cancelled': cancelled,
      },
    );

    Future<void> seedForwardingRoute() async {
      await writer.execute('''
TRUNCATE public.trust_evidence, public.notification_outbox,
  public.attention_occurrence_recipient, public.attention_occurrence,
  public.user_block, public.beacon, public."user" CASCADE
''');
      var slot = 0;
      for (final entry in _names.entries) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
          parameters: {
            'id': entry.key,
            'name': entry.value,
            'key': pgTestPublicKey('forwardhelped', ++slot),
          },
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, @title, 'Moving day', @status)
'''),
        parameters: {
          'id': _beacon,
          'author': _author,
          'title': _title,
          'status': BeaconStatus.open.smallintValue,
        },
      );
      // Winning route A -> F1 -> F2 -> H, plus a newer cancelled arrival
      // through an off-path person. Only the canonical live route earns thanks.
      await forward('FfhelpAFirst', _author, _first, hoursAgo: 6);
      await forward(
        'FfhelpFirstSecond',
        _first,
        _second,
        parent: 'FfhelpAFirst',
        hoursAgo: 5,
      );
      await forward(
        'FfhelpSecondHelper',
        _second,
        _helper,
        parent: 'FfhelpFirstSecond',
        hoursAgo: 4,
      );
      await forward('FfhelpAOffpath', _author, _offPath, hoursAgo: 3);
      await forward(
        'FfhelpOffpathHelper',
        _offPath,
        _helper,
        parent: 'FfhelpAOffpath',
        hoursAgo: 2,
        cancelled: true,
      );
    }

    setUp(seedForwardingRoute);

    Future<void> accept(String helper) async {
      await offers.offerHelp(beaconId: _beacon, userId: helper);
      await coordination.acceptHelpOffer(
        beaconId: _beacon,
        offerUserId: helper,
        actorUserId: _author,
      );
    }

    Future<List<Map<String, dynamic>>> receipts(String account) async => [
      for (final row in await writer.execute(
        Sql.named('''
SELECT id, requires_action, seen_at, cleared_at, suppression_class, presentation_payload
FROM public.notification_outbox
WHERE beacon_id = @beacon AND account_id = @account
  AND presentation_payload->>'eventType' = 'forwardHelped'
ORDER BY id
'''),
        parameters: {'beacon': _beacon, 'account': account},
      ))
        row.toColumnMap(),
    ];

    Future<List<Map<String, Object?>>> activity() async {
      final Object? result = await updates.attentionFeed.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: _first),
        'view': 'all',
        'surface': 'activity',
      });
      final page = (result! as Map)['page'] as Map;
      return (page['items'] as List).cast<Map<String, Object?>>();
    }

    // A newer general update belongs on the change line alongside the thanks.
    // Its timestamp is strictly newer without a wall-clock sleep.
    Future<void> addNewerGeneralUpdate({required bool closed}) =>
        writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, created_at, beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy
)
SELECT 'NcardGeneral', @account, 'requestProgress', 'roomActivityLowPriority',
  'normal', 'Request status changed', '', '/#/view/' || @beacon,
  'card-general', MAX(created_at) + interval '1 second', @beacon,
  'card-general', 'beacon', 'request_status_changed',
  jsonb_build_object('eventType', 'requestStatusChanged', 'personal', false,
    'toStatus', @status::text), 'standard', 'beacon_content'
FROM public.notification_outbox WHERE beacon_id = @beacon
'''),
          parameters: {
            'account': _first,
            'beacon': _beacon,
            'status': closed ? 'closed' : 'open',
          },
        );

    Map<String, Object?> helpedPayload(Map<String, Object?> receipt) =>
        (jsonDecode(receipt['presentationPayloadJson']! as String) as Map)
            .cast<String, Object?>();

    Future<void> expectHelpedCard({required bool done}) async {
      // Main Activity has two legitimate Request-card representatives:
      // pinned offers and grouped stream cards. Neither is History.
      final Object? offersPage = await updates.activityOffers.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: _first),
      });
      final pinnedCards = ((offersPage! as Map)['items'] as List)
          .cast<Map<String, Object?>>()
          .where((row) => row['beaconId'] == _beacon);
      final streamCards = (await activity())
          .where(
            (row) =>
                row['beaconId'] == _beacon &&
                row['itemKind'] == 'requestActivity',
          )
          .toList();
      final cards = [...pinnedCards, ...streamCards];
      expect(
        cards,
        hasLength(1),
        reason: 'the live optional receipt has a main Activity Request card',
      );
      final preview = (cards.single['eventsPreview']! as List)
          .cast<Map<String, Object?>>();
      expect(
        preview.any((row) => row['id'] == 'NcardGeneral'),
        isTrue,
        reason: 'the Request change line is still present',
      );
      final thanks = preview
          .where((row) => helpedPayload(row)['eventType'] == 'forwardHelped')
          .toList();
      expect(
        thanks,
        hasLength(1),
        reason:
            "a newer change must not displace the forwarder's own row into History",
      );
      expect(helpedPayload(thanks.single)['done'] == true, done);
      expect(thanks.single['requiresAction'], isFalse);
      expect(thanks.single['actorUserId'], isNull);
    }

    Future<void> closeRequest() async {
      await getIt<ClosureCase>().close(authorId: _author, beaconId: _beacon);
      final rows = await writer.execute(
        Sql.named('SELECT status FROM public.beacon WHERE id = @id'),
        parameters: {'id': _beacon},
      );
      expect(rows.single.single, BeaconStatus.closed.smallintValue);
    }

    Future<void> dismiss(String id) async {
      final clear = getIt<AttentionClearCase>();
      final snapshot = await clear.captureSnapshot(
        accountId: _first,
        kind: AttentionClearCaptureKind.explicit,
        receiptId: id,
      );
      expect(snapshot.receiptIds, [id]);
      final result = await clear.clear(
        accountId: _first,
        operationId: const Uuid().v4(),
        snapshotToken: snapshot.token,
      );
      expect(result.appliedReceiptIds, [id]);
    }

    test(
      'a completed forward-helped receipt keeps its own row after the Request closes',
      () async {
        await accept(_helper);
        await closeRequest();
        final stored = (await receipts(_first)).single;
        expect((stored['presentation_payload'] as Map)['done'], isTrue);
        expect(stored['cleared_at'], isNull);
        await addNewerGeneralUpdate(closed: true);
        await expectHelpedCard(done: true);
        await dismiss(stored['id'] as String);
        for (var reload = 0; reload < 2; reload++) {
          final cards = await activity();
          final events = cards.expand(
            (row) => (row['eventsPreview'] as List? ?? const [])
                .cast<Map<String, Object?>>(),
          );
          expect(
            events.where(
              (row) => helpedPayload(row)['eventType'] == 'forwardHelped',
            ),
            isEmpty,
          );
        }
      },
    );

    test(
      'dismissing before close permits one uncleared Done receipt on the main Activity card',
      () async {
        await accept(_helper);
        final id = (await receipts(_first)).single['id'] as String;
        await dismiss(id);
        expect((await receipts(_first)).single['cleared_at'], isNotNull);
        await closeRequest();
        final done = await receipts(_first);
        expect(
          done,
          hasLength(1),
          reason:
              'finalization restores one receipt, without duplicating the accepted variant',
        );
        expect((done.single['presentation_payload'] as Map)['done'], isTrue);
        expect(
          done.single['cleared_at'],
          isNull,
          reason: 'a dismissed accepted receipt must return as Done',
        );
        await addNewerGeneralUpdate(closed: true);
        await expectHelpedCard(done: true);
      },
    );

    test(
      'a newer Request change keeps the accepted forward-helped receipt on its Activity card',
      () async {
        await accept(_helper);
        expect(await receipts(_first), hasLength(1));
        await addNewerGeneralUpdate(closed: false);
        await expectHelpedCard(done: false);
      },
    );
  }, skip: skipReason);
}
