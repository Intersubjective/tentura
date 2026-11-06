@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/commitment_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
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
// acceptance and closure actions, rather than called directly by this test.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_HELPED_UPDATES_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_helped',
  );
  final skipReason = await pgSkipReason(target);

  group('forwarders see the help their forwards brought', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late HelpOfferCase offers;
    late CoordinationCase coordination;
    late ClosureCase closure;
    late AttentionAckPort acknowledgements;
    late QueryAttention updates;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
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
      database = getIt<TenturaDb>();
      offers = getIt<HelpOfferCase>();
      coordination = getIt<CoordinationCase>();
      closure = getIt<ClosureCase>();
      acknowledgements = getIt<AttentionAckPort>();
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

    setUp(() async {
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
    });

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
SELECT id, requires_action, seen_at, suppression_class, presentation_payload
FROM public.notification_outbox
WHERE beacon_id = @beacon AND account_id = @account
  AND presentation_payload->>'eventType' = 'forwardHelped'
ORDER BY id
'''),
        parameters: {'beacon': _beacon, 'account': account},
      ))
        row.toColumnMap(),
    ];

    Future<List<Map<String, Object?>>> visibleUpdates(
      String account, {
      bool unread = false,
    }) async {
      final Object? result = await updates.attentionFeed.resolve!(null, {
        kGlobalInputQueryJwt: JwtEntity(sub: account),
        'view': unread ? 'unread' : 'all',
      });
      if (result case {'page': {'items': final List<Object?> items}}) {
        return [
          for (final item in items)
            if (item case final Map<String, Object?> fields)
              fields
            else
              throw StateError('Updates returned an invalid receipt'),
        ];
      }
      throw StateError('Updates returned an invalid page');
    }

    Map<String, Object?> payload(Map<String, Object?> item) {
      if (item['presentationPayloadJson'] case final String json) {
        final Object? decoded = jsonDecode(json);
        if (decoded case final Map<String, Object?> fields) return fields;
      }
      throw StateError('Updates returned an invalid presentation payload');
    }

    Future<Map<String, Object?>> helpedUpdate(
      String account, {
      bool unread = false,
    }) async {
      final items = (await visibleUpdates(account, unread: unread))
          .where((item) => payload(item)['eventType'] == 'forwardHelped')
          .toList();
      expect(items, hasLength(1), reason: 'one visible forward-help update');
      return items.single;
    }

    Future<void> finalize() async {
      // With fewer than three members close() invokes the real finalizer
      // immediately. No clock manipulation or direct finalizer invocation.
      await closure.close(authorId: _author, beaconId: _beacon);
      final epoch = await ClosureRepository(database).latestEpoch(_beacon);
      expect(epoch, isNotNull);
      expect(epoch!.status, ClosureEpochStatus.finalized);
      expect(epoch.finalizedAt, isNotNull);
    }

    test('acceptance thanks every canonical path forwarder in Updates '
        'without a My desk obligation', () async {
      await accept(_helper);

      for (final account in [_first, _second]) {
        final stored = await receipts(account);
        expect(stored, hasLength(1), reason: '$account forwarded on the path');
        expect(stored.single['requires_action'], isFalse);
        expect(stored.single['suppression_class'], 'standard');
        final item = await helpedUpdate(account, unread: true);
        expect(item['id'], stored.single['id']);
        expect(item['requiresAction'], isFalse);
        expect(item['title'], contains('Your forward helped'));
        expect(item['title'], isNot(contains('Done')));
        expect(payload(item), containsPair('beaconId', _beacon));
        expect(payload(item), containsPair('beaconTitle', _title));
        expect(payload(item), containsPair('helperId', _helper));
        expect(payload(item), containsPair('authorId', _author));
        expect(payload(item)['path'], [
          _named(_author),
          _named(_first),
          _named(_second),
          _named(_helper),
        ]);
        final obligations = await updates.liveObligationBeacons.resolve!(null, {
          kGlobalInputQueryJwt: JwtEntity(sub: account),
        });
        expect(obligations, isNot(contains(_beacon)));
        final summary =
            await updates.attentionSurfaceSummary.resolve!(null, {
                  kGlobalInputQueryJwt: JwtEntity(sub: account),
                })
                as Map;
        expect(summary['myDeskCount'], 0);
        expect(summary['myDeskDot'], isFalse);
      }
      for (final account in [_author, _helper, _otherHelper, _offPath]) {
        expect(
          await receipts(account),
          isEmpty,
          reason: '$account is not a path forwarder',
        );
        expect(
          (await visibleUpdates(account)).where(
            (item) => payload(item)['eventType'] == 'forwardHelped',
          ),
          isEmpty,
        );
      }
    });

    test('another accepted helper through the same forwarder updates one '
        'item to two people', () async {
      await accept(_helper);
      final before = await receipts(_first);
      await forward(
        'FfhelpFirstOther',
        _first,
        _otherHelper,
        parent: 'FfhelpAFirst',
        hoursAgo: 1,
      );
      await accept(_otherHelper);

      for (final account in [_author, _helper, _otherHelper]) {
        expect(
          await receipts(account),
          isEmpty,
          reason: 'later acceptances still thank only path forwarders',
        );
        expect(
          (await visibleUpdates(account)).where(
            (item) => payload(item)['eventType'] == 'forwardHelped',
          ),
          isEmpty,
        );
      }
      expect(await receipts(_first), hasLength(1));
      final after = await helpedUpdate(_first);
      expect(before, hasLength(1));
      expect(after['id'], before.single['id']);
      expect(after['collapsedCount'], 2);
      expect(after['title'], contains('Your forward helped 2 people'));
      final second = await helpedUpdate(_second);
      expect(
        second['collapsedCount'],
        1,
        reason: 'the second helper bypassed F2',
      );
      expect(await receipts(_second), hasLength(1));
      expect(await receipts(_otherHelper), isEmpty);
    });

    test('finalization upgrades the same read items to Done and makes them '
        'unread again', () async {
      await accept(_helper);
      final before = <String, List<Map<String, dynamic>>>{};
      final marked = <String, int>{};
      final seen = <String, List<Map<String, dynamic>>>{};
      for (final account in [_first, _second]) {
        before[account] = await receipts(account);
        marked[account] = await acknowledgements.markSeen(
          accountId: account,
          ids: before[account]!.map((row) => row['id'] as String).toList(),
        );
        seen[account] = await receipts(account);
      }

      await finalize();

      for (final account in [_first, _second]) {
        expect(await receipts(account), hasLength(1));
        final item = await helpedUpdate(account, unread: true);
        expect(before[account], hasLength(1));
        expect(marked[account], 1);
        expect(seen[account]!.single['seen_at'], isNotNull);
        expect(item['id'], before[account]!.single['id']);
        expect(item['title'], contains('Done ✓'));
        expect(item['seenAt'], isNull);
        expect(item['requiresAction'], isFalse);
        expect(item['collapsedCount'], 1);
      }
    });

    test(
      'finalization upgrades a shared forwarder receipt for a retained '
      'helper and leaves the withdrawn-only forwarder receipt unchanged',
      () async {
        await accept(_helper);
        await forward(
          'FfhelpFirstOther',
          _first,
          _otherHelper,
          parent: 'FfhelpAFirst',
          hoursAgo: 1,
        );
        await accept(_otherHelper);
        final before = <String, List<Map<String, dynamic>>>{};
        final marked = <String, int>{};
        final seen = <String, List<Map<String, dynamic>>>{};
        final visibleBefore = <String, List<Map<String, Object?>>>{};
        for (final account in [_first, _second]) {
          before[account] = await receipts(account);
          visibleBefore[account] = (await visibleUpdates(account))
              .where((item) => payload(item)['eventType'] == 'forwardHelped')
              .toList();
          marked[account] = await acknowledgements.markSeen(
            accountId: account,
            ids: before[account]!.map((row) => row['id'] as String).toList(),
          );
          seen[account] = await receipts(account);
        }
        // Keep H's voluntary departure in the closure snapshot by moving their
        // commitment history beyond the existing acknowledgement grace window.
        await writer.execute(
          Sql.named('''
UPDATE public.beacon_commitment_event
SET created_at = created_at - make_interval(secs => @elapsedSeconds)
WHERE beacon_id = @beacon AND user_id = @helper
'''),
          parameters: {
            'elapsedSeconds': kCommitmentGracePeriod.inSeconds + 1,
            'beacon': _beacon,
            'helper': _helper,
          },
        );
        await offers.withdraw(
          beaconId: _beacon,
          userId: _helper,
          withdrawReason: 'timing',
        );

        await finalize();

        final epoch = (await ClosureRepository(database).latestEpoch(_beacon))!;
        final members = await ClosureRepository(database).members(
          beaconId: _beacon,
          epoch: epoch.epoch,
        );
        expect(members, hasLength(2));
        expect(
          members.singleWhere((member) => member.userId == _helper).departure,
          Departure.voluntary,
        );
        expect(
          members
              .singleWhere((member) => member.userId == _otherHelper)
              .departure,
          isNull,
        );
        for (final account in [_author, _helper, _otherHelper]) {
          expect(
            await receipts(account),
            isEmpty,
            reason: 'finalization still thanks only path forwarders',
          );
          expect(
            (await visibleUpdates(account)).where(
              (item) => payload(item)['eventType'] == 'forwardHelped',
            ),
            isEmpty,
          );
        }
        for (final account in [_first, _second]) {
          expect(await receipts(account), hasLength(1));
          expect(before[account], hasLength(1));
          expect(marked[account], 1);
          expect(seen[account]!.single['seen_at'], isNotNull);
          expect(visibleBefore[account], hasLength(1));
        }
        // F1 brought both helpers; H2 is still present. Its one collapsed item
        // upgrades even though H withdrew, and the historical count stays two.
        final first = await helpedUpdate(_first, unread: true);
        expect(first['id'], before[_first]!.single['id']);
        expect(first['title'], contains('Done ✓'));
        expect(first['seenAt'], isNull);
        expect(first['collapsedCount'], 2);
        expect(first['requiresAction'], isFalse);
        // F2 brought only H: its old receipt, copy, payload and read timestamp
        // survive finalization without receiving H2's unrelated Done upgrade.
        final second = await helpedUpdate(_second);
        expect(second['id'], before[_second]!.single['id']);
        expect(second['title'], visibleBefore[_second]!.single['title']);
        expect(second['body'], visibleBefore[_second]!.single['body']);
        expect(
          second['presentationPayloadJson'],
          visibleBefore[_second]!.single['presentationPayloadJson'],
        );
        expect(second['title'], isNot(contains('Done')));
        expect(second['collapsedCount'], 1);
        expect(
          (await receipts(_second)).single['seen_at'],
          seen[_second]!.single['seen_at'],
        );
        expect(second['seenAt'], isNotNull);
        expect(second['requiresAction'], isFalse);
      },
    );

    test('a withdrawn helper leaves the forwarders update intact and read '
        'without a Done upgrade at finalization', () async {
      await accept(_helper);
      final before = <String, List<Map<String, dynamic>>>{};
      final marked = <String, int>{};
      for (final account in [_first, _second]) {
        before[account] = await receipts(account);
        marked[account] = await acknowledgements.markSeen(
          accountId: account,
          ids: before[account]!.map((row) => row['id'] as String).toList(),
        );
      }
      await offers.withdraw(
        beaconId: _beacon,
        userId: _helper,
        withdrawReason: 'timing',
      );
      final afterWithdrawal = <String, List<Map<String, dynamic>>>{
        for (final account in [_first, _second])
          account: await receipts(account),
      };
      // A direct helper keeps an actual closure epoch, but their route has
      // no forwarder. Thus finalize runs without crediting F1/F2 for them.
      await forward('FfhelpADirect', _author, _otherHelper, hoursAgo: 1);
      await accept(_otherHelper);
      await finalize();
      final epoch = (await ClosureRepository(database).latestEpoch(_beacon))!;
      final members = await ClosureRepository(
        database,
      ).members(beaconId: _beacon, epoch: epoch.epoch);
      expect(
        members
            .where((member) => member.departure == null)
            .map((member) => member.userId),
        [_otherHelper],
      );
      for (final account in [_first, _second]) {
        final stored = await receipts(account);
        expect(stored, hasLength(1));
        final item = await helpedUpdate(account);
        expect(before[account], hasLength(1));
        expect(marked[account], 1);
        expect(afterWithdrawal[account], hasLength(1));
        expect(
          afterWithdrawal[account]!.single['id'],
          before[account]!.single['id'],
        );
        expect(item['id'], before[account]!.single['id']);
        expect(
          stored.single['presentation_payload'],
          before[account]!.single['presentation_payload'],
        );
        expect(item['title'], isNot(contains('Done')));
        expect(item['seenAt'], isNotNull);
        expect(item['collapsedCount'], 1);
      }
    });

    test('withdrawing the only accepted helper preserves the same read '
        'forwarder receipts without Done when finalized', () async {
      await accept(_helper);
      final before = <String, List<Map<String, dynamic>>>{};
      final marked = <String, int>{};
      final seen = <String, List<Map<String, dynamic>>>{};
      for (final account in [_first, _second]) {
        before[account] = await receipts(account);
        marked[account] = await acknowledgements.markSeen(
          accountId: account,
          ids: before[account]!.map((row) => row['id'] as String).toList(),
        );
        seen[account] = await receipts(account);
      }
      // Match the closure lifecycle fixtures: move past the acknowledgement
      // grace window without waiting a day. Inside that window withdrawal
      // voids membership, so close() would skip the finalizer entirely.
      await writer.execute(
        Sql.named('''
UPDATE public.beacon_commitment_event
SET created_at = created_at - make_interval(secs => @elapsedSeconds)
WHERE beacon_id = @beacon AND user_id = @helper
'''),
        parameters: {
          'elapsedSeconds': kCommitmentGracePeriod.inSeconds + 1,
          'beacon': _beacon,
          'helper': _helper,
        },
      );
      await offers.withdraw(
        beaconId: _beacon,
        userId: _helper,
        withdrawReason: 'timing',
      );
      final afterWithdrawal = <String, List<Map<String, dynamic>>>{
        for (final account in [_first, _second])
          account: await receipts(account),
      };

      await finalize();

      final epoch = (await ClosureRepository(database).latestEpoch(_beacon))!;
      final members = await ClosureRepository(database).members(
        beaconId: _beacon,
        epoch: epoch.epoch,
      );
      expect(
        members,
        hasLength(1),
        reason: 'no replacement helper was admitted',
      );
      expect(members.single.userId, _helper);
      expect(members.single.departure, Departure.voluntary);
      for (final account in [_first, _second]) {
        final stored = await receipts(account);
        expect(
          stored,
          hasLength(1),
          reason: 'withdrawal never retracts the update',
        );
        expect(before[account], hasLength(1));
        expect(marked[account], 1);
        expect(afterWithdrawal[account], hasLength(1));
        final original = before[account]!.single;
        expect(afterWithdrawal[account]!.single['id'], original['id']);
        expect(stored.single['id'], original['id']);
        expect(
          stored.single['presentation_payload'],
          original['presentation_payload'],
        );
        expect(seen[account]!.single['seen_at'], isNotNull);
        expect(stored.single['seen_at'], seen[account]!.single['seen_at']);
        final item = await helpedUpdate(account);
        expect(item['id'], original['id']);
        expect(item['title'], contains('Your forward helped'));
        expect(item['title'], isNot(contains('Done')));
        expect(item['seenAt'], isNotNull);
        expect(item['collapsedCount'], 1);
      }
    });

    for (final reverseBlock in [false, true]) {
      test(
        'the Updates payload masks a path person who '
        '${reverseBlock ? 'blocked the recipient' : 'the recipient blocked'}',
        () async {
          await writer.execute(
            Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocker)
'''),
            parameters: {
              'blocker': reverseBlock ? _second : _first,
              'blocked': reverseBlock ? _first : _second,
            },
          );
          await accept(_helper);

          final first = await helpedUpdate(_first);
          expect(payload(first)['path'], [
            _named(_author),
            _named(_first),
            _anonymous(1),
            _named(_helper),
          ]);
          final publicCopy = jsonEncode(first);
          expect(publicCopy, isNot(contains(_second)));
          expect(publicCopy, isNot(contains(_names[_second])));
          final second = await helpedUpdate(_second);
          expect(payload(second)['path'], [
            _named(_author),
            _anonymous(1),
            _named(_second),
            _named(_helper),
          ]);
          expect(await receipts(_first), hasLength(1));
          expect(await receipts(_second), hasLength(1));
        },
      );
    }

    test('an acceptance cannot commit when its forwarder receipt cannot '
        'be saved', () async {
      await offers.offerHelp(beaconId: _beacon, userId: _helper);
      await writer.execute(r'''
CREATE FUNCTION public.reject_forward_helped_test_receipt() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.presentation_payload->>'eventType' = 'forwardHelped' THEN
    RAISE EXCEPTION 'forward helped receipt unavailable';
  END IF;
  RETURN NEW;
END;
$$;
''');
      await writer.execute('''
CREATE TRIGGER reject_forward_helped_test_receipt
BEFORE INSERT OR UPDATE ON public.notification_outbox
FOR EACH ROW EXECUTE FUNCTION public.reject_forward_helped_test_receipt();
''');
      try {
        await expectLater(
          coordination.acceptHelpOffer(
            beaconId: _beacon,
            offerUserId: _helper,
            actorUserId: _author,
          ),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains(
                'forward helped receipt unavailable',
              ),
            ),
          ),
          reason: 'acceptance and every path receipt are one atomic action',
        );
        final admitted = await writer.execute(
          Sql.named(
            'SELECT count(*) FROM public.beacon_participant WHERE beacon_id = @beacon AND user_id = @helper',
          ),
          parameters: {'beacon': _beacon, 'helper': _helper},
        );
        expect(admitted.single.single, 0);
        for (final account in [_first, _second, _helper]) {
          expect(await receipts(account), isEmpty);
        }
      } finally {
        await writer.execute(
          'DROP TRIGGER reject_forward_helped_test_receipt ON public.notification_outbox',
        );
        await writer.execute(
          'DROP FUNCTION public.reject_forward_helped_test_receipt()',
        );
      }
    });
  }, skip: skipReason);
}

Matcher _named(String id) => allOf(
  containsPair('userId', id),
  containsPair('displayName', _names[id]),
  containsPair('anonymousCount', 0),
);

Matcher _anonymous(int count) => allOf(
  containsPair('userId', null),
  containsPair('displayName', null),
  containsPair('anonymousCount', count),
);
