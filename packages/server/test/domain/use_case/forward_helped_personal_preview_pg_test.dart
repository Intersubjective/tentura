@Tags(['pg', 'mr', 'multi-connection', 'repo-files'])
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';
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
    envVarName: 'TENTURA_FORWARD_HELPED_PREVIEW_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_helped_preview',
  );
  final skipReason = await pgSkipReason(target);

  group('Activity previews reserve space for forwarding thanks', () {
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

    Future<List<Map<String, Object?>>> pinned() async {
      final Object? result = await updates.activityOffers.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: _first),
      });
      return ((result! as Map)['items'] as List).cast<Map<String, Object?>>();
    }

    Future<List<Map<String, Object?>>> preview({required bool isPinned}) async {
      final cards = (await (isPinned ? pinned() : activity()))
          .where(
            (row) =>
                row['beaconId'] == _beacon &&
                (isPinned || row['itemKind'] == 'requestActivity'),
          )
          .toList();
      expect(
        cards,
        hasLength(1),
        reason: 'the Request has one card on this surface',
      );
      return (cards.single['eventsPreview']! as List)
          .cast<Map<String, Object?>>();
    }

    List<String> personalIds(List<Map<String, Object?>> rows) => [
      for (final row in rows)
        if (helpedPayload(row)['personal'] == true &&
            helpedPayload(row)['eventType'] != 'forwardHelped')
          row['id']! as String,
    ];

    Future<void> insertPersonal(int start, int end, String helpedId) async {
      // Pairs share a timestamp so both the cap boundary and cursor pages
      // must break ties by id, rather than relying on insertion order.
      for (var i = start; i < end; i++) {
        final id = 'Npersonal${i.toString().padLeft(2, '0')}';
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, created_at, beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy
)
SELECT @id, @account, 'requestProgress', 'roomActivityLowPriority',
  'normal', 'A personal Request update', '', '/#/view/' || @beacon,
  @id, created_at + make_interval(secs => @seconds), @beacon,
  @id, 'beacon', 'request_status_changed',
  jsonb_build_object('eventType', 'requestStatusChanged', 'personal', true,
    'toStatus', 'open'), 'standard', 'beacon_content'
FROM public.notification_outbox WHERE id = @helped
'''),
          parameters: {
            'id': id,
            'account': _first,
            'beacon': _beacon,
            'seconds': 1 + i ~/ 2,
            'helped': helpedId,
          },
        );
      }
    }

    Future<List<String>> seededEventOrder(String helpedId) async {
      final rows =
          (await writer.execute(
              Sql.named('''
SELECT id, created_at FROM public.notification_outbox
WHERE account_id = @account AND beacon_id = @beacon
  AND (id = @helped OR id = 'NcardGeneral' OR id LIKE 'Npersonal%')
'''),
              parameters: {
                'account': _first,
                'beacon': _beacon,
                'helped': helpedId,
              },
            )).map((row) => row.toColumnMap()).toList()
            // Derive the oracle from fixture timestamps, independently of insertion
            // numbers and of the production query's cursor/ranking implementation.
            ..sort((a, b) {
              final byTime = (b['created_at'] as DateTime).compareTo(
                a['created_at'] as DateTime,
              );
              return byTime != 0
                  ? byTime
                  : (b['id'] as String).compareTo(a['id'] as String);
            });
      return rows.map((row) => row['id'] as String).toList();
    }

    Future<void> expectCountLimitedLog(List<String> expected) async {
      final actual = <String>[];
      final seenIds = <String>{};
      String? cursor;
      for (var pageNumber = 0; pageNumber < 10; pageNumber++) {
        final Object? result = await updates.activityAttention.resolve!(null, {
          kGlobalInputQueryJwt: const JwtEntity(sub: _first),
          'beaconId': _beacon,
          'limit': 7,
          'cursor': ?cursor,
        });
        final page = result! as Map;
        final events = (page['events'] as List).cast<Map<String, Object?>>();
        final pageIds = events.map((row) => row['id']! as String).toList();
        expect(
          events.length,
          lessThanOrEqualTo(7),
          reason: 'every event-log page respects the requested limit',
        );
        expect(
          pageIds.toSet(),
          hasLength(pageIds.length),
          reason: 'an event appears only once within a page',
        );
        expect(
          pageIds.where(seenIds.contains),
          isEmpty,
          reason: 'cursor pages never repeat an event from an earlier page',
        );
        seenIds.addAll(pageIds);
        expect(
          pageIds,
          expected.skip(actual.length).take(7).toList(),
          reason: 'the event log uses count and chronological order only',
        );
        actual.addAll(pageIds);
        cursor = page['nextCursor'] as String?;
        if (cursor == null) break;
      }
      expect(cursor, isNull, reason: 'pagination terminates');
      expect(actual, expected);
    }

    for (final isPinned in [false, true]) {
      for (final personalCount in [20, 21, 25]) {
        for (final helpedIsNewest in [false, true]) {
          final surface = isPinned
              ? 'pinned offer'
              : 'Activity stream Request card';
          final chronology = helpedIsNewest ? 'newer' : 'older';
          test(
            '$surface keeps $chronology forwarding thanks with $personalCount personal receipts and 20 personal slots',
            () async {
              await accept(_helper);
              // Pin a stored boolean so payload stripping cannot accidentally
              // pass as a comparison between two absent values.
              await writer.execute(
                Sql.named('''
UPDATE public.notification_outbox
SET presentation_payload = presentation_payload || '{"done": false}'::jsonb
WHERE account_id = @account AND beacon_id = @beacon
  AND presentation_payload->>'eventType' = 'forwardHelped'
'''),
                parameters: {'account': _first, 'beacon': _beacon},
              );
              final stored = (await receipts(_first)).single;
              final helpedId = stored['id'] as String;
              final storedPayload = (stored['presentation_payload'] as Map)
                  .cast<String, Object?>();
              expect(stored['cleared_at'], isNull);
              // The real forwarding route leaves an unanswered offer. Watching
              // moves its Request into the stream; an unanswered offer stays pinned.
              if (!isPinned) {
                await writer.execute(
                  Sql.named('''
UPDATE public.inbox_item SET status = 1
WHERE user_id = @account AND beacon_id = @beacon
'''),
                  parameters: {'account': _first, 'beacon': _beacon},
                );
              }

              await insertPersonal(0, 3, helpedId);
              final sparse = await preview(isPinned: isPinned);
              expect(personalIds(sparse), [
                'Npersonal02',
                'Npersonal01',
                'Npersonal00',
              ]);
              expect(
                sparse
                    .where(
                      (row) =>
                          helpedPayload(row)['eventType'] == 'forwardHelped',
                    )
                    .map((row) => row['id']),
                [helpedId],
                reason: 'an unsaturated preview includes thanks exactly once',
              );

              await insertPersonal(3, personalCount, helpedId);
              if (helpedIsNewest) {
                await writer.execute(
                  Sql.named('''
UPDATE public.notification_outbox SET created_at = (
  SELECT MAX(created_at) + interval '1 second'
  FROM public.notification_outbox WHERE beacon_id = @beacon
) WHERE id = @id
'''),
                  parameters: {'beacon': _beacon, 'id': helpedId},
                );
              }
              await addNewerGeneralUpdate(closed: false);
              final expectedLog = await seededEventOrder(helpedId);
              expect(expectedLog, hasLength(personalCount + 2));
              await expectCountLimitedLog(expectedLog);
              final orderedPersonal = expectedLog
                  .where((id) => id.startsWith('Npersonal'))
                  .toList();
              expect(orderedPersonal, hasLength(personalCount));
              final newestPersonal = orderedPersonal.take(20).toList();
              final excludedPersonal = orderedPersonal.skip(20).toSet();
              final saturated = await preview(isPinned: isPinned);
              expect(
                saturated
                    .where(
                      (row) =>
                          helpedPayload(row)['eventType'] == 'forwardHelped',
                    )
                    .map((row) => row['id'])
                    .toList(),
                [helpedId],
                reason:
                    '$surface must show exactly the stored forwarding thanks '
                    'when $personalCount personal receipts saturate its preview',
              );
              expect(
                personalIds(saturated).where(excludedPersonal.contains),
                isEmpty,
                reason:
                    'receipts older than the newest 20 stay out of the preview',
              );

              final clear = getIt<AttentionClearCase>();
              final snapshot = await clear.captureSnapshot(
                accountId: _first,
                kind: AttentionClearCaptureKind.explicit,
                receiptId: helpedId,
              );
              expect(snapshot.receiptIds, [helpedId]);
              final cleared = await clear.clear(
                accountId: _first,
                operationId: const Uuid().v4(),
                snapshotToken: snapshot.token,
              );
              expect(cleared.appliedReceiptIds, [helpedId]);
              final afterClear = await preview(isPinned: isPinned);
              expect(personalIds(afterClear), newestPersonal);
              for (final card in [
                ...await activity(),
                ...await pinned(),
              ].where((row) => row['beaconId'] == _beacon)) {
                final events = (card['eventsPreview']! as List)
                    .cast<Map<String, Object?>>();
                expect(
                  events.where(
                    (row) => helpedPayload(row)['eventType'] == 'forwardHelped',
                  ),
                  isEmpty,
                );
              }

              // Assert the captured pre-dismissal preview after checking the other
              // public paths, so the baseline failure cannot hide a broken fixture.
              expect(
                saturated
                    .where(
                      (row) =>
                          helpedPayload(row)['personal'] != true &&
                          helpedPayload(row)['eventType'] != 'forwardHelped',
                    )
                    .map((row) => row['id']),
                ['NcardGeneral'],
              );
              final thanks = saturated
                  .where(
                    (row) => helpedPayload(row)['eventType'] == 'forwardHelped',
                  )
                  .toList();
              expect(
                {
                  'personalIds': personalIds(saturated),
                  'thanks': [
                    for (final row in thanks)
                      {
                        'id': row['id'],
                        'eventType': helpedPayload(row)['eventType'],
                        'done': helpedPayload(row)['done'],
                        'requiresAction': row['requiresAction'],
                        'actorUserId': row['actorUserId'],
                      },
                  ],
                },
                {
                  'personalIds': newestPersonal,
                  'thanks': [
                    {
                      'id': helpedId,
                      'eventType': 'forwardHelped',
                      'done': storedPayload['done'],
                      'requiresAction': false,
                      'actorUserId': null,
                    },
                  ],
                },
                reason:
                    'thanks have an independent slot and preserve their controls',
              );
              expect(saturated, hasLength(22));
            },
          );
        }
      }
    }
  }, skip: skipReason);
}
