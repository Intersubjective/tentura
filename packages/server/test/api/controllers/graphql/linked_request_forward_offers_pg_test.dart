@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_wake_port.dart';
import 'package:tentura_server/domain/port/phantom_pending_forward_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/phantom_forward_delivery_case.dart';
import 'package:tentura_server/domain/use_case/phantom_merge_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/owner_graph_contention.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'U0ffe10000001';
const _anna = 'U0ffe10000002';
const _other = 'U0ffe10000003';
const _note = 'see this';
const _title = 'Help with the garden';
const _secondTitle = 'Repair a bicycle';

typedef _Row = Map<String, Object?>;
typedef _SavedForward = ({String id, String request, String invite});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_LINKED_FORWARD_OFFERS_TEST_DB',
    defaultNamePrefix: 'tentura_test_linked_forward_offers',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Saved Request forwards after linking an existing account', () {
    late _Fixture fixture;
    late String entry;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      await enforceOwnerScope(session);
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      getIt.registerSingleton<PhantomMergeWakePort>(
        const PhantomMergeWakePort.disabled(),
      );
      await configureSessionDatabaseTestGraph(target.databaseEnv);
      final router = await getIt.getAsync<RootRouter>();
      fixture = _Fixture(session.writer, router.routeHandler());
    });

    setUp(() async {
      await fixture.reset();
      entry = await fixture.createEntry();
    });

    test(
      'offers each saved Request only to the owner with localized copy',
      () async {
        final first = await fixture.saveForward(entry);
        final second = await fixture.saveForward(entry, title: _secondTitle);
        final emptyEntry = await fixture.createEntry();
        await fixture.link(emptyEntry, _other);
        expect(await fixture.ownerOfferCards(), isEmpty);
        final before = await fixture.attentionFor(_anna);

        final merge = await fixture.link(entry, _anna);

        await fixture.expectNoLinkAttention(_anna, before, [first, second]);
        await fixture.expectAttention(_other, (
          events: const [],
          outbox: const [],
        ));
        for (final saved in [first, second]) {
          expect(await fixture.forwardEdges(saved.request), isEmpty);
        }
        final cards = await fixture.ownerOfferCards();
        expect(
          {
            'owner cards': cards.length,
            'saved forwards': [
              for (final saved in [first, second])
                await fixture.savedRow(saved),
            ],
          },
          {
            'owner cards': 2,
            'saved forwards': everyElement(_offeredFor(merge, _anna)),
          },
        );
        expect(
          cards.map((card) => card['occurrence_id']).toSet(),
          hasLength(2),
        );
        final titlesByForwardId = {first.id: _title, second.id: _secondTitle};
        final cardForwardIds = <String>[];
        final internalWords = RegExp('phantom|фантом', caseSensitive: false);
        for (final card in cards) {
          final source = card['source_event_key']! as String;
          final forwardId = source.split(':').last;
          cardForwardIds.add(forwardId);
          final title = titlesByForwardId[forwardId];
          expect(title, isNotNull, reason: 'Unexpected offer source $source');
          final en = await fixture.renderCard(card, 'en');
          final ru = await fixture.renderCard(card, 'ru');
          expect(en.sentence, 'Forward «$title» to Anna now?');
          for (final copy in [en, ru]) {
            expect(copy.sentence, isNotEmpty);
            expect(copy.sentence, isNot(matches(internalWords)));
            expect(copy.headline, isNot(matches(internalWords)));
          }
        }
        expect(cardForwardIds, unorderedEquals(titlesByForwardId.keys));
      },
    );

    test(
      'linking a closed Request keeps its offer private through the delivery sweep',
      () async {
        final saved = await fixture.saveForward(entry);
        await fixture.close(saved.request);
        final before = await fixture.attentionFor(_anna);
        final ownerCardsBefore = await fixture.ownerOfferCards();

        final merge = await fixture.link(entry, _anna);

        await fixture.expectNoLinkAttention(_anna, before, [saved]);
        expect(await fixture.forwardEdges(saved.request), isEmpty);
        final offerAfterLink = await fixture.savedRow(saved);
        final ownerCardsAfterLink = await fixture.ownerOfferCards();

        await getIt<PhantomForwardDeliveryCase>().sweep();

        await fixture.expectNoLinkAttention(_anna, before, [saved]);
        expect(await fixture.forwardEdges(saved.request), isEmpty);
        expect(await fixture.savedRow(saved), offerAfterLink);
        expect(offerAfterLink, _offeredFor(merge, _anna));
        expect(ownerCardsAfterLink, hasLength(ownerCardsBefore.length + 1));
      },
    );

    for (final sweep in [true, false]) {
      test(
        sweep
            ? 'the delivery sweep forwards an invite claim and leaves a manual offer alone'
            : 'direct delivery forwards an invite claim and leaves a manual offer alone',
        () async {
          final offered = await fixture.saveForward(entry);
          final merge = await fixture.link(entry, _anna);
          final inviteEntry = await fixture.createEntry();
          final claimed = await fixture.saveForward(inviteEntry);
          final inviteMerge = await fixture.acceptWithoutDelivery(
            inviteEntry,
            claimed.invite,
            _other,
          );
          expect(
            await fixture.savedRow(claimed),
            containsPair('state', 'claimed'),
          );
          final offerBefore = await fixture.savedRow(offered);

          final delivery = getIt<PhantomForwardDeliveryCase>();
          if (sweep) {
            await delivery.sweep();
          } else {
            await delivery.deliver([
              fixture.deliveryClaim(offered, merge),
              fixture.deliveryClaim(claimed, inviteMerge),
            ]);
          }

          expect(
            await fixture.savedRow(claimed),
            containsPair('state', 'delivered'),
          );
          expect(await fixture.forwardEdges(claimed.request), [
            containsPair('recipient_id', _other),
          ]);
          expect(await fixture.forwardEdges(offered.request), isEmpty);
          await fixture.expectAttention(_anna, (
            events: const [],
            outbox: const [],
          ));
          final offerAfter = await fixture.savedRow(offered);
          expect(offerAfter, _offeredFor(merge, _anna));
          expect(offerAfter, offerBefore);
        },
      );
    }

    test(
      'confirmation sends the saved note once and gives the recipient ordinary forward attention',
      () async {
        final saved = await fixture.saveForward(entry);
        final merge = await fixture.link(entry, _anna);
        expect(await fixture.forwardEdges(saved.request), isEmpty);
        final before = await fixture.attentionFor(_anna);

        final reply = await fixture.confirm(saved);
        expect(reply['errors'], isNull, reason: jsonEncode(reply));

        final edges = await fixture.forwardEdges(saved.request);
        expect(edges, [
          allOf(
            containsPair('sender_id', _owner),
            containsPair('recipient_id', _anna),
            containsPair('note', _note),
            containsPair('cancelled_at', null),
          ),
        ]);
        final delivered = await fixture.savedRow(saved);
        expect(
          delivered,
          allOf(
            containsPair('state', 'delivered'),
            containsPair('merge_id', merge),
            containsPair('recipient_id', _anna),
            containsPair('forward_edge_id', edges.single['id']),
          ),
        );
        final after = await fixture.attentionFor(_anna);
        expect(
          after.events.where(
            (event) => !before.events.any(
              (prior) => prior['id'] == event['id'],
            ),
          ),
          [
            allOf(
              containsPair('event_type', 'relayReceived'),
              containsPair('actor_user_id', _owner),
            ),
          ],
        );

        final repeated = await fixture.confirm(saved);
        expect(await fixture.forwardEdges(saved.request), edges);
        expect(await fixture.savedRow(saved), delivered);
        await fixture.expectAttention(_anna, after);
        _expectNotFound(repeated);
      },
    );

    test(
      'confirmation of a closed Request returns the ordinary forward error',
      () async {
        final saved = await fixture.saveForward(entry);
        final merge = await fixture.link(entry, _anna);
        await fixture.close(saved.request);
        final ordinary = _singleError(await fixture.forward(saved.request));
        expect(_errorCode(ordinary), '1102');
        expect(ordinary['message'], isNotEmpty);
        final offerBefore = await fixture.savedRow(saved);

        final reply = await fixture.confirm(saved);

        expect(await fixture.forwardEdges(saved.request), isEmpty);
        expect(
          await fixture.savedRow(saved),
          anyOf(offerBefore, {
            ...offerBefore,
            'state': 'lapsed',
            'forward_edge_id': null,
            'lapse_reason': isNotEmpty,
            'resolved_at': isA<DateTime>(),
          }),
          reason: 'A refusal may preserve the offer or record a lapse.',
        );
        final error = _singleError(reply);
        expect(error['message'], ordinary['message']);
        expect(_errorCode(error), _errorCode(ordinary));
        expect(offerBefore, _offeredFor(merge, _anna));
      },
    );

    test(
      'confirmation is refused for another caller and for an owner who has no offer',
      () async {
        final offered = await fixture.saveForward(entry);
        final merge = await fixture.link(entry, _anna);
        final pending = await fixture.saveForward(await fixture.createEntry());
        final offeredBefore = await fixture.savedRow(offered);
        final pendingBefore = await fixture.savedRow(pending);

        final wrongCaller = await fixture.confirm(offered, actor: _anna);
        final noOffer = await fixture.confirm(pending);

        expect(await fixture.forwardEdges(offered.request), isEmpty);
        expect(await fixture.forwardEdges(pending.request), isEmpty);
        expect(await fixture.savedRow(offered), offeredBefore);
        expect(await fixture.savedRow(pending), pendingBefore);
        _expectNotFound(wrongCaller);
        _expectNotFound(noOffer);
        expect(offeredBefore, _offeredFor(merge, _anna));
        expect(pendingBefore, _pending);
      },
    );

    test(
      'undoing a manual link withdraws its offer and the next link offers it to the new recipient',
      () async {
        final saved = await fixture.saveForward(entry);
        final firstMerge = await fixture.link(entry, _anna);
        final firstOffer = await fixture.savedRow(saved);

        await fixture.unmerge(entry, firstMerge);
        expect(await fixture.savedRow(saved), _pending);
        final withdrawn = await fixture.confirm(saved);
        expect(await fixture.forwardEdges(saved.request), isEmpty);

        final secondMerge = await fixture.link(entry, _other);
        expect(secondMerge, isNot(firstMerge));
        expect(await fixture.forwardEdges(saved.request), isEmpty);
        expect(await fixture.savedRow(saved), _offeredFor(secondMerge, _other));
        expect(firstOffer, _offeredFor(firstMerge, _anna));
        _expectNotFound(withdrawn);
      },
    );

    test(
      'undoing an invite restores the outstanding claim and preserves other forwards',
      () async {
        final earlier = await fixture.link(entry, _other);
        await fixture.unmerge(entry, earlier);
        final stale = await fixture.saveForward(entry, title: 'Earlier offer');
        // A separate historical offer is needed to distinguish same-entry rows
        // of the undone merge from rows of the current merge.
        await fixture.seedHistoricalOffer(stale, earlier, _other);
        final claimed = await fixture.saveForward(entry);
        final delivered = await fixture.saveForward(entry, title: 'Delivered');
        final lapsed = await fixture.saveForward(entry, title: 'Closed');
        final merge = await fixture.acceptWithoutDelivery(
          entry,
          claimed.invite,
          _anna,
        );
        await fixture.close(lapsed.request);
        await getIt<PhantomForwardDeliveryCase>().deliver([
          fixture.deliveryClaim(delivered, merge),
          fixture.deliveryClaim(lapsed, merge),
        ]);
        expect(
          await fixture.savedRow(claimed),
          allOf(
            containsPair('state', 'claimed'),
            containsPair('merge_id', merge),
            containsPair('recipient_id', _anna),
          ),
        );
        final deliveredBefore = await fixture.savedRow(delivered);
        final lapsedBefore = await fixture.savedRow(lapsed);
        expect(
          deliveredBefore,
          allOf(
            containsPair('state', 'delivered'),
            containsPair('merge_id', merge),
          ),
        );
        expect(
          lapsedBefore,
          allOf(
            containsPair('state', 'lapsed'),
            containsPair('merge_id', merge),
            containsPair('recipient_id', _anna),
            containsPair('forward_edge_id', null),
            containsPair('resolved_at', isA<DateTime>()),
            containsPair('lapse_reason', isNotEmpty),
          ),
        );
        final deliveredEdges = await fixture.forwardEdges(delivered.request);
        expect(deliveredEdges, [
          containsPair('id', deliveredBefore['forward_edge_id']),
        ]);
        final lapsedEdges = await fixture.forwardEdges(lapsed.request);
        expect(lapsedEdges, isEmpty);
        final earlierBefore = await fixture.savedRow(stale);

        final otherEntry = await fixture.createEntry();
        final unrelated = await fixture.saveForward(
          otherEntry,
          title: 'Other entry',
        );
        final otherMerge = await fixture.link(otherEntry, _other);
        final unrelatedBefore = await fixture.savedRow(unrelated);

        await fixture.unmerge(entry, merge);
        expect(await fixture.savedRow(claimed), _pending);
        expect(await fixture.savedRow(delivered), deliveredBefore);
        expect(await fixture.savedRow(lapsed), lapsedBefore);
        expect(await fixture.forwardEdges(delivered.request), deliveredEdges);
        expect(await fixture.forwardEdges(lapsed.request), lapsedEdges);
        await getIt<PhantomForwardDeliveryCase>().sweep();

        expect(await fixture.savedRow(claimed), _pending);
        expect(await fixture.forwardEdges(claimed.request), isEmpty);
        expect(await fixture.savedRow(delivered), deliveredBefore);
        expect(await fixture.savedRow(lapsed), lapsedBefore);
        expect(await fixture.forwardEdges(delivered.request), deliveredEdges);
        expect(await fixture.forwardEdges(lapsed.request), lapsedEdges);
        expect(await fixture.savedRow(stale), earlierBefore);
        expect(await fixture.forwardEdges(stale.request), isEmpty);
        expect(await fixture.savedRow(unrelated), unrelatedBefore);
        expect(await fixture.forwardEdges(unrelated.request), isEmpty);

        final deliveredReply = await fixture.confirm(delivered);
        final lapsedReply = await fixture.confirm(lapsed);
        expect(await fixture.forwardEdges(delivered.request), deliveredEdges);
        expect(await fixture.forwardEdges(lapsed.request), lapsedEdges);
        _expectNotFound(deliveredReply);
        _expectNotFound(lapsedReply);
        expect(unrelatedBefore, _offeredFor(otherMerge, _other));
      },
    );
  }, skip: skip);
}

Matcher _offeredFor(String merge, String recipient) => allOf(
  containsPair('state', 'offered'),
  containsPair('merge_id', merge),
  containsPair('recipient_id', recipient),
  containsPair('forward_edge_id', null),
);

final _pending = allOf(
  containsPair('state', 'pending'),
  containsPair('merge_id', null),
  containsPair('recipient_id', null),
  containsPair('forward_edge_id', null),
);

_Row _singleError(_Row reply) {
  expect(reply['data'], isNull, reason: jsonEncode(reply));
  expect(reply['errors'], hasLength(1), reason: jsonEncode(reply));
  return ((reply['errors']! as List<Object?>).single! as Map)
      .cast<String, Object?>();
}

void _expectNotFound(_Row reply) {
  expect(_errorCode(_singleError(reply)), '1002', reason: jsonEncode(reply));
}

Object? _errorCode(_Row error) =>
    (error['extensions'] as Map<String, Object?>?)?['code'];

typedef _Attention = ({List<_Row> events, List<_Row> outbox});

final class _Fixture {
  const _Fixture(this.writer, this.handler);

  final Connection writer;
  final Handler handler;

  Future<Result> _sql(
    String statement, [
    Map<String, Object?> parameters = const {},
  ]) => writer.execute(Sql.named(statement), parameters: parameters);

  Future<void> reset() async {
    await writer.execute(
      'TRUNCATE public."user", public.attention_occurrence CASCADE',
    );
    for (final (index, (id, name)) in [
      (_owner, 'Vadim'),
      (_anna, 'Anna'),
      (_other, 'Boris'),
    ].indexed) {
      await _sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
''',
        {
          'id': id,
          'name': name,
          'key': pgTestPublicKey('forwardoffers', index + 1),
        },
      );
    }
    await _sql(
      '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@owner, @anna, 1), (@owner, @other, 1),
       (@anna, @owner, 1), (@other, @owner, 1)
''',
      {'owner': _owner, 'anna': _anna, 'other': _other},
    );
  }

  Future<String> createEntry() =>
      getIt<PhantomCase>().create(ownerId: _owner, name: 'Neighbour');

  Future<_SavedForward> saveForward(
    String entry, {
    String title = _title,
  }) async {
    final result = await _sql(
      '''
INSERT INTO public.beacon (
  user_id, title, description, status, kind, is_discoverable, published_at
)
VALUES (@owner, @title, 'Saturday morning', 0, 0, false, now())
RETURNING id
''',
      {'owner': _owner, 'title': title},
    );
    final request = result.single.single! as String;
    final invite = await getIt<PhantomCase>().forwardRequest(
      ownerId: _owner,
      phantomId: entry,
      beaconId: request,
      note: _note,
    );
    final rows = await _sql(
      '''
SELECT id, state, note FROM public.phantom_pending_forward
WHERE phantom_id = @entry AND beacon_id = @request AND sender_id = @owner
''',
      {'entry': entry, 'request': request, 'owner': _owner},
    );
    expect(rows, hasLength(1));
    final row = rows.single.toColumnMap();
    expect(
      row,
      allOf(containsPair('state', 'pending'), containsPair('note', _note)),
    );
    return (id: row['id']! as String, request: request, invite: invite);
  }

  Future<_Row> savedRow(_SavedForward saved) async => (await _sql(
    '''
SELECT * FROM public.phantom_pending_forward WHERE id = @id
''',
    {'id': saved.id},
  )).single.toColumnMap();

  Future<List<_Row>> forwardEdges(String request) async => [
    for (final row in await _sql(
      '''
SELECT * FROM public.beacon_forward_edge WHERE beacon_id = @request ORDER BY id
''',
      {'request': request},
    ))
      row.toColumnMap(),
  ];

  Future<String> currentMerge(String entry) async {
    final rows = await _sql(
      'SELECT current_merge_id FROM public.phantom WHERE id = @entry',
      {'entry': entry},
    );
    final merge = rows.single.single;
    expect(merge, isA<String>());
    return merge! as String;
  }

  Future<void> close(String request) async {
    await getIt<ClosureCase>().close(authorId: _owner, beaconId: request);
  }

  Future<void> expectAttention(String recipient, _Attention expected) async {
    final actual = await attentionFor(recipient);
    expect(actual.events, expected.events);
    expect(actual.outbox, expected.outbox);
  }

  Future<void> expectNoLinkAttention(
    String recipient,
    _Attention before,
    List<_SavedForward> savedForwards,
  ) async {
    final after = await attentionFor(recipient);
    for (final saved in savedForwards) {
      expect(
        after.events.map((event) => event['source_event_key']),
        isNot(contains('requestForwardLapsed:${saved.id}')),
      );
      expect(
        after.outbox.where((receipt) {
          final source = receipt['source_event_key'];
          if (source is! String) {
            fail('Expected a recipient receipt source key');
          }
          return source == saved.id ||
              source.endsWith(':${saved.id}') ||
              receipt['target_entity_id'] == saved.id;
        }),
        isEmpty,
        reason: 'No recipient outbox row for saved forward ${saved.id}',
      );
    }
    expect(
      after.events,
      before.events,
      reason: 'Recipient attention occurrences',
    );
    expect(
      after.outbox,
      before.outbox,
      reason: 'Recipient notification outbox',
    );
  }

  Future<_Attention> attentionFor(String recipient) async => (
    events: [
      for (final row in await _sql(
        '''
SELECT e.id, e.source_event_key, e.event_type, e.actor_user_id
FROM public.attention_occurrence e
JOIN public.attention_occurrence_recipient r ON r.occurrence_id = e.id
WHERE r.account_id = @recipient ORDER BY e.id
''',
        {'recipient': recipient},
      ))
        row.toColumnMap(),
    ],
    outbox: [
      for (final row in await _sql(
        '''
SELECT id, occurrence_id, source_event_key, presentation_key, target_entity_id
FROM public.notification_outbox WHERE account_id = @recipient ORDER BY id
''',
        {'recipient': recipient},
      ))
        row.toColumnMap(),
    ],
  );

  Future<List<_Row>> ownerOfferCards() async => [
    for (final row in await _sql(
      '''
SELECT e.id AS occurrence_id, e.source_event_key, o.beacon_id, o.actor_user_id,
       o.presentation_key, o.presentation_payload, o.kind
FROM public.notification_outbox o
JOIN public.attention_occurrence e ON e.id = o.occurrence_id
JOIN public.attention_occurrence_recipient r
  ON r.occurrence_id = e.id AND r.account_id = o.account_id
WHERE o.account_id = @owner AND e.event_type <> 'phantomMerged'
''',
      {'owner': _owner},
    ))
      row.toColumnMap(),
  ];

  Future<NotificationCopy> renderCard(_Row card, String locale) async {
    final identity = (await getIt<NotificationIdentityPort>().resolve(_owner, [
      IdentityRequest(
        beaconId: card['beacon_id'] as String? ?? '',
        actorId: card['actor_user_id'] as String?,
      ),
    ])).single;
    return const NotificationCopyRenderer().render(
      presentationKey: card['presentation_key']! as String,
      kind: NotificationKind.values.byName(card['kind']! as String),
      facts: (card['presentation_payload']! as Map).cast<String, Object?>(),
      identity: identity,
      locale: locale,
      tzOffsetMinutes: 0,
      now: DateTime.timestamp(),
    );
  }

  Future<String> link(String entry, String recipient) async {
    final reply = await _graphql(
      r'mutation Link($entry: String!, $recipient: String!) {'
      r' phantomLink(phantomId: $entry, userId: $recipient) }',
      {'entry': entry, 'recipient': recipient},
    );
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    expect(reply['data'], {'phantomLink': true});
    return currentMerge(entry);
  }

  Future<void> unmerge(String entry, String merge) async {
    final reply = await _graphql(
      r'mutation Unlink($entry: String!, $merge: String!) {'
      r' phantomUnmerge(phantomId: $entry, mergeId: $merge) }',
      {'entry': entry, 'merge': merge},
    );
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    expect(reply['data'], {'phantomUnmerge': true});
  }

  // Planned wire operation. Invoking it over GraphQL allows the test to
  // compile before the operation exists and requires a real domain response.
  Future<_Row> confirm(_SavedForward saved, {String actor = _owner}) =>
      _graphql(
        r'mutation Confirm($id: String!) { phantomForwardConfirm(id: $id) }',
        {'id': saved.id},
        actor: actor,
      );

  Future<_Row> forward(String request) => _graphql(
    r'mutation Forward($id: String!, $recipients: [String!]) {'
    r' beaconForward(id: $id, recipientIds: $recipients) { batchId } }',
    {
      'id': request,
      'recipients': [_anna],
    },
  );

  Future<_Row> _graphql(
    String query,
    _Row variables, {
    String actor = _owner,
  }) async {
    final token = getIt<AuthCase>().issueAccessToken(actor).rawToken;
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://127.0.0.1:2080/api/v2/graphql'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as _Row;
  }

  Future<String> acceptWithoutDelivery(
    String entry,
    String invite,
    String recipient,
  ) async {
    expect(
      await getIt<InvitationCase>().acceptAsExisting(
        code: invite,
        userId: recipient,
      ),
      InviteAcceptance.accepted,
    );
    // The worker commits the real merge and claims. Stop only the separate
    // post-commit transaction, simulating an interruption before delivery.
    final merge = PhantomMergeCase(
      getIt<OwnerGraphTransactionPort>(),
      getIt<PhantomRepositoryPort>(),
      getIt<PhantomMergeRepositoryPort>(),
      getIt<UserBlockRepositoryPort>(),
      getIt<PhantomPendingForwardRepositoryPort>(),
      PhantomForwardDeliveryCase(
        const _InterruptedDelivery(),
        getIt<PostLockPort>(),
        getIt<PhantomPendingForwardRepositoryPort>(),
        getIt<TransactionalAttentionCase>(),
        getIt<ForwardCase>(),
        Logger('Interrupted saved-forward delivery'),
      ),
      Logger('Invite merge test'),
    );
    await merge.runDue(
      leaseOwner: 'forward-offers-test',
      clock: DateTime.timestamp,
    );
    return currentMerge(entry);
  }

  PhantomForwardClaim deliveryClaim(_SavedForward saved, String merge) => (
    id: saved.id,
    senderId: _owner,
    beaconId: saved.request,
    parentForwardEdgeId: null,
    mergeId: merge,
  );

  Future<void> seedHistoricalOffer(
    _SavedForward saved,
    String merge,
    String recipient,
  ) async {
    await writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
UPDATE public.phantom_pending_forward
SET state = 'offered', merge_id = @merge, recipient_id = @recipient
WHERE id = @id
'''),
      parameters: {'id': saved.id, 'merge': merge, 'recipient': recipient},
    );
    expect(await savedRow(saved), _offeredFor(merge, recipient));
  }
}

final class _InterruptedDelivery implements OwnerGraphTransactionPort {
  const _InterruptedDelivery();

  @override
  Future<T> run<T>(
    Set<String> ownerIds,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body,
  ) async => throw StateError('Worker interrupted after committing the merge');

  @override
  Future<T> runRepeatableRead<T>(
    String ownerId,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body, {
    int maxAttempts = 3,
  }) => throw UnsupportedError('Delivery requires a write transaction');
}
