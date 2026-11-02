@Tags(['pg'])
@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_beacon_display.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

// The Requests list asks the server for two batches per screen of cards:
// InboxRoomContextBatch (room membership, unread count, latest line…) and
// BeaconDisplayStatuses (phase, tier, actions). A viewer with many rooms
// must cost the same handful of statements as a viewer with a few: a read
// per Request, repeated for every card, is what pushed both operations past
// the five-second request deadline.
//
// The tests run the production GraphQL fields over the generated
// application graph (real use cases, repositories and a one-connection
// pool), count the SQL statements each operation sends, and replay them on
// a separate connection to inspect the actual plans.
//
// When a request does hit its deadline mid-batch, the connection must come
// back clean: one error for the caller, no CouldNotRollBackException, no
// session left inside a transaction, and the next request on the same
// single-connection pool succeeds.
//
// Not covered here: wall-clock timings. They depend on the host and on
// production data volume; they are measured on the perf database and
// recorded with the change.

const _viewer = 'Ubatchview0001';
const _author = 'Ubatchauth0001';
const _helper = 'Ubatchhelp0001';
const _crowdAuthor = 'Ubatchcrowd001';

/// Requests the viewer authored (coordination tier, room member).
const _ownRequests = 40;

/// Requests by [_author] the viewer was admitted to (room member).
const _admittedRequests = 24;

/// Published Requests by [_author] forwarded to the viewer: readable, not
/// a room the viewer is in.
const _publicRequests = 8;

/// Unpublished Requests by [_author]: unreadable for the viewer.
const _hiddenRequests = 8;

/// Requests by [_crowdAuthor], never asked about: they make the room tables
/// large, as in production, so a read that is not keyed by the requested
/// Requests shows up in the plan.
const _crowdRequests = 160;
const _crowdMessagesPerRequest = 100;

/// Messages per batch Request older than the viewer's watermark.
const _seenMessages = 8;

/// Messages per batch Request after the viewer's watermark, by [_helper].
const _unreadMessages = 4;

const _messagesPerRequest = _seenMessages + _unreadMessages;

/// Statement boundaries at which the deadline test fires the deadline: more
/// than one per-Request read cycle of either batch today.
const _deadlinePoints = 8;

const _requestCount =
    _ownRequests + _admittedRequests + _publicRequests + _hiddenRequests;

const _inboxDocument = r'''
query InboxRoomContextBatch($beaconIds: [String!]!) {
  InboxRoomContextBatch(beaconIds: $beaconIds) {
    postRootExcerpt
    beaconId
    isRoomMember
    currentLine
    lastRoomMeaningfulChange
    nextMoveText
    roomUnreadCount
    lastSeenAt
    openBlockerTitle
    openBlockerCreatorId
    openBlockerTargetPersonId
    openBlockerResponsibleUserId
    openBlockerCreatedAt
    openBlockerCreatorDisplayName
    openBlockerCreatorImageId
    openBlockerCreatorHasPicture
    publicFactSnippet
    planSliceJson
    lastActivityAt
    lastMessageAt
    lastMessageText
    lastMessageAuthorId
    lastMessageAuthorName
    lastMessageKind
    parentBeaconId
    parentTitle
  }
}
''';

const _displayDocument = r'''
query BeaconDisplayStatuses($beaconIds: [String!]!) {
  beaconDisplayStatuses(beaconIds: $beaconIds) {
    beaconId
    status
    phase
    suggestedAction
    slot2Kind
    tier
    reviewClosesAt
    lastActivityAt
    lifecycleEndedAt
    canCancel
    canDelete
    everAcknowledgedCommitterCount
  }
}
''';

String _ownId(int i) => 'Bbatchown${i.toString().padLeft(5, '0')}';
String _admittedId(int i) => 'Bbatchadm${i.toString().padLeft(5, '0')}';
String _publicId(int i) => 'Bbatchpub${i.toString().padLeft(5, '0')}';
String _hiddenId(int i) => 'Bbatchhid${i.toString().padLeft(5, '0')}';

/// Every Request the Requests list asks about, in list order.
final _allIds = [
  for (var i = 0; i < _ownRequests; i++) _ownId(i),
  for (var i = 0; i < _admittedRequests; i++) _admittedId(i),
  for (var i = 0; i < _publicRequests; i++) _publicId(i),
  for (var i = 0; i < _hiddenRequests; i++) _hiddenId(i),
];

/// A short list with the same mix of Requests: some authored, some admitted,
/// one public, one hidden.
final _fewIds = [
  for (var i = 0; i < 5; i++) _ownId(i),
  for (var i = 0; i < 3; i++) _admittedId(i),
  _publicId(0),
  _hiddenId(0),
];

final _roomIds = {
  for (var i = 0; i < _ownRequests; i++) _ownId(i),
  for (var i = 0; i < _admittedRequests; i++) _admittedId(i),
};

final _readableIds = {
  ..._roomIds,
  for (var i = 0; i < _publicRequests; i++) _publicId(i),
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_LIST_BATCH_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_list_batch',
  );
  final unavailable = await pgSkipReason(target);

  group('Requests list batch reads for a viewer with many rooms', () {
    late DisposablePgWriterSession session;
    late Env env;
    late _StatementCapture capture;
    late Handler graphql;
    late List<SentryEvent> events;

    setUpAll(() async {
      if (unavailable != null) return;
      session = await setUpDisposablePgWriter(target: target);
      await _seed(session.writer);

      final databaseEnv = target.databaseEnv;
      env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicOrigin: 'http://127.0.0.1:2080',
        pgHost: databaseEnv.pgHost,
        pgPort: databaseEnv.pgPort,
        pgDatabase: databaseEnv.pgDatabase,
        pgUsername: databaseEnv.pgUsername,
        pgPassword: databaseEnv.pgPassword,
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        printEnv: false,
        isDebugModeOn: true,
        workersCount: 1,
        // One connection: a request that leaves it dirty breaks the next.
        maxConnectionCount: 1,
        sentryDsn: 'https://public@o123.ingest.sentry.io/1',
      );

      // The production graph, with every repository's database handle
      // recording the statements it sends through its leased scope.
      capture = _StatementCapture();
      getIt
        ..skipDoubleRegistration = true
        ..registerFactory<TenturaDb>(
          () => TenturaDb.scoped(
            getIt<MainDbPool>(),
            scopeInterceptor: () => capture,
          ),
        );
      await configureSessionDatabaseTestGraph(env);
      expect(env.pgPoolSettings.maxConnectionCount, 1);

      events = <SentryEvent>[];
      await Sentry.close();
      await Sentry.init((options) {
        options
          ..dsn = env.sentryDsn
          // Surface failures in test callbacks rather than swallowing them.
          // ignore: invalid_use_of_internal_member
          ..automatedTestMode = true
          ..tracesSampleRate = 1.0
          ..beforeSend = (event, hint) {
            final filtered = scrubAndFilterSentryEvent(event, hint);
            if (filtered != null) events.add(filtered);
            return null;
          }
          ..beforeSendTransaction = (transaction, hint) => null;
      });

      final controller = GraphqlController(
        env,
        schema: TenturaGraphQL(
          GraphQLSchema(
            queryType: GraphQLObjectType('Query', 'Query root')
              ..fields.addAll([
                QueryBeaconRoom().inboxRoomContextBatch,
                QueryBeaconDisplay().beaconDisplayStatuses,
              ]),
          ),
        ),
      );
      graphql = requestContextIoAdapter(
        sentryRequestTracing(env: env)(
          (request) => capture.duringRequest(
            () => controller.handler(
              request.change(
                context: {kContextJwtKey: const JwtEntity(sub: _viewer)},
              ),
            ),
          ),
        ),
      );
    });

    tearDownAll(() async {
      if (unavailable != null) return;
      await Sentry.close();
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() {
      if (unavailable != null) return;
      capture.reset();
      events.clear();
    });

    Future<Map<String, Object?>> post(
      String document,
      String operation,
      List<String> ids,
    ) async {
      final response = await graphql(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'query': document,
            'operationName': operation,
            'variables': {'beaconIds': ids},
          }),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, Object?>;
    }

    Future<List<Map<String, Object?>>> rows(
      String document,
      String operation,
      String field,
      List<String> ids,
    ) async {
      final body = await post(document, operation, ids);
      expect(body['errors'], isNull, reason: jsonEncode(body));
      final data = body['data']! as Map<String, Object?>;
      return (data[field]! as List<Object?>).cast<Map<String, Object?>>();
    }

    /// The statements one operation sends for [ids].
    Future<List<_Statement>> statementsFor(
      String document,
      String operation,
      String field,
      List<String> ids,
    ) async {
      capture.reset();
      await rows(document, operation, field, ids);
      return List.of(capture.statements);
    }

    // Coverage map: issue item 1 and its QA sequence use the production
    // Request-card batch shared by My desk, Watching and Activity. The QA
    // sequence below covers an admitted helper; the role-parameterized batch
    // tests cover real, system and non-system plan-updated lines for authors,
    // admitted helpers and stewards through the same GraphQL operation.
    // The client in-room unread divider is out of scope. No UI is changed,
    // so phone/locale/input checks are n/a for this server-only regression.
    test(
      'an admitted helper sees only real messages as unread through admissions '
      'declines and Enough help in the Request card batch',
      () async {
        const id = 'Bunreadbatch1';
        await session.writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$id', '$_author', 'Entrance help', '', 0, now())
''');
        await session.writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$id', '$_author', '$_viewer')
''');
        final offers = getIt<HelpOfferCase>();
        final coordination = getIt<CoordinationCase>();
        final counts = <Object?>[];

        // This Request is forwarded to the viewer, who has never opened it.
        await offers.offerHelp(beaconId: id, userId: _viewer);
        await coordination.acceptHelpOffer(
          beaconId: id,
          offerUserId: _viewer,
          actorUserId: _author,
        );
        Future<Map<String, Object?>> card() async => (await rows(
          _inboxDocument,
          'InboxRoomContextBatch',
          'InboxRoomContextBatch',
          [id],
        )).single;

        final admitted = await card();
        expect(admitted['isRoomMember'], isTrue);
        expect(admitted['lastSeenAt'], isNull);
        expect(admitted['lastMessageText'], isNull);
        counts.add(admitted['roomUnreadCount']);

        await getIt<BeaconRoomCase>().createMessage(
          beaconId: id,
          userId: _author,
          body: 'Meet at the entrance',
        );
        final withMessage = await card();
        expect(withMessage['lastMessageText'], 'Meet at the entrance');
        counts.add(withMessage['roomUnreadCount']);

        // Set up two more readable offers, then use the real admission,
        // decline and status commands rather than inventing system rows.
        for (final user in [_helper, _crowdAuthor]) {
          await session.writer.execute(
            pg.Sql.named('''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id) VALUES (@id, @author, @user)
'''),
            parameters: {'id': id, 'author': _author, 'user': user},
          );
          await offers.offerHelp(beaconId: id, userId: user);
        }
        await coordination.acceptHelpOffer(
          beaconId: id,
          offerUserId: _helper,
          actorUserId: _author,
        );
        await coordination.declineHelpOffer(
          beaconId: id,
          offerUserId: _crowdAuthor,
          actorUserId: _author,
          reason: 'We have enough helpers',
        );
        await coordination.setBeaconStatus(
          beaconId: id,
          authorUserId: _author,
          status: 8,
        );
        final afterSystemActivity = await card();
        expect(afterSystemActivity['lastMessageText'], 'Meet at the entrance');
        expect(afterSystemActivity['lastSeenAt'], isNull);
        counts.add(afterSystemActivity['roomUnreadCount']);
        expect(
          counts,
          [0, 1, 1],
          reason:
              'Admission and status activity must '
              'not inflate the count beside the real-message preview',
        );
      },
      skip: unavailable,
    );

    for (final (role, roleBits) in [
      ('author', BeaconParticipantRoleBits.author),
      ('admitted helper', BeaconParticipantRoleBits.helper),
      ('steward', BeaconParticipantRoleBits.steward),
    ]) {
      test(
        'Request card batch counts real and plan-updated messages but skips '
        'system lines for viewer role $role',
        () async {
          final id = 'Bbatchrole$roleBits';
          final authorId = role == 'author' ? _viewer : _author;
          await session.writer.execute(
            pg.Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES (@id, @author, 'Entrance help', '', 0, now())
'''),
            parameters: {'id': id, 'author': authorId},
          );
          await session.writer.execute(
            pg.Sql.named('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES (@id, @viewer, @role, 0, 3)
'''),
            parameters: {'id': id, 'viewer': _viewer, 'role': roleBits},
          );
          if (role == 'steward') {
            await session.writer.execute(
              pg.Sql.named('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@id, @viewer)
'''),
              parameters: {'id': id, 'viewer': _viewer},
            );
          }
          await session.writer.execute(
            pg.Sql.named('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, semantic_marker, system_message_kind, created_at)
VALUES
  (@id, @sender, 'Meet at the entrance', NULL, NULL, '2026-01-04T13:00:00Z'),
  (@id, @sender, '', @planMarker, NULL, '2026-01-04T14:00:00Z'),
  (@id, @sender, '', NULL, @systemKind, '2026-01-04T15:00:00Z')
'''),
            parameters: {
              'id': id,
              'sender': _helper,
              'planMarker': BeaconRoomSemanticMarker.updatePlan,
              'systemKind': BeaconRoomSystemMessageKind.statusChanged,
            },
          );

          final card = (await rows(
            _inboxDocument,
            'InboxRoomContextBatch',
            'InboxRoomContextBatch',
            [id],
          )).single;
          expect(card['isRoomMember'], isTrue);
          expect(card['lastSeenAt'], isNull);
          expect(card['lastMessageText'], 'Meet at the entrance');
          // System activity still moves Recent ordering, even though it
          // neither becomes the preview nor contributes to unread counts.
          expect(
            DateTime.parse(card['lastActivityAt']! as String),
            DateTime.utc(2026, 1, 4, 15),
          );
          expect(card['roomUnreadCount'], 2);
        },
        skip: unavailable,
      );
    }

    test(
      'InboxRoomContextBatch answers every card of a long list in as many '
      'statements as a short one, each reading only the requested rooms',
      () async {
        // What the client sees for the long list.
        final inbox = await rows(
          _inboxDocument,
          'InboxRoomContextBatch',
          'InboxRoomContextBatch',
          _allIds,
        );
        expect(inbox.map((row) => row['beaconId']), _allIds);
        for (final row in inbox) {
          final id = row['beaconId']! as String;
          final member = _roomIds.contains(id);
          expect(row['isRoomMember'], member, reason: id);
          expect(
            row['roomUnreadCount'],
            member ? _unreadMessages : 0,
            reason: id,
          );
          expect(
            row['lastMessageText'],
            member ? 'Unread ${_unreadMessages - 1} in $id' : isNull,
            reason: id,
          );
        }

        final few = await statementsFor(
          _inboxDocument,
          'InboxRoomContextBatch',
          'InboxRoomContextBatch',
          _fewIds,
        );
        final many = await statementsFor(
          _inboxDocument,
          'InboxRoomContextBatch',
          'InboxRoomContextBatch',
          _allIds,
        );
        expect(few, isNotEmpty);

        final violations = [
          if (many.length > few.length)
            _notBatched(
              'InboxRoomContextBatch',
              many: many.length,
              few: few.length,
            ),
          for (final statement in many)
            ...await _planViolations(
              session.writer,
              statement,
              requested: _requestCount,
              requestedMessages: _roomIds.length * _messagesPerRequest,
            ),
        ];
        expect(violations, isEmpty, reason: violations.take(20).join('\n'));
      },
      skip: unavailable,
    );

    test(
      'BeaconDisplayStatuses answers every card of a long list in as many '
      'statements as a short one, each reading only the requested Requests',
      () async {
        final statuses = await rows(
          _displayDocument,
          'BeaconDisplayStatuses',
          'beaconDisplayStatuses',
          _allIds,
        );
        // Only Requests the viewer may read, in list order; authored and
        // admitted ones in the coordination tier.
        expect(
          statuses.map((row) => row['beaconId']),
          _allIds.where(_readableIds.contains),
        );
        for (final row in statuses) {
          final id = row['beaconId']! as String;
          expect(
            row['tier'],
            _roomIds.contains(id) ? 'coordination' : 'public',
            reason: id,
          );
        }
        final own = statuses.firstWhere((row) => row['beaconId'] == _ownId(0));
        expect(own['canDelete'], isTrue);

        final few = await statementsFor(
          _displayDocument,
          'BeaconDisplayStatuses',
          'beaconDisplayStatuses',
          _fewIds,
        );
        final many = await statementsFor(
          _displayDocument,
          'BeaconDisplayStatuses',
          'beaconDisplayStatuses',
          _allIds,
        );
        expect(few, isNotEmpty);

        final violations = [
          if (many.length > few.length)
            _notBatched(
              'BeaconDisplayStatuses',
              many: many.length,
              few: few.length,
            ),
          for (final statement in many)
            ...await _planViolations(
              session.writer,
              statement,
              requested: _requestCount,
              requestedMessages: _roomIds.length * _messagesPerRequest,
            ),
        ];
        expect(violations, isEmpty, reason: violations.take(20).join('\n'));
      },
      skip: unavailable,
    );

    for (final (operation, document, field) in [
      ('InboxRoomContextBatch', _inboxDocument, 'InboxRoomContextBatch'),
      ('BeaconDisplayStatuses', _displayDocument, 'beaconDisplayStatuses'),
    ]) {
      test(
        'a $operation request whose deadline fires anywhere early in the '
        'batch fails once, is never reported as a failed rollback, and '
        'leaves the single pooled connection usable for the next request',
        () async {
          var failedAtDeadline = 0;
          // The five-second timer can fire between any two statements of a
          // slow batch, inside a unit of work or outside one.
          for (var after = 1; after <= _deadlinePoints; after++) {
            final at = 'Deadline after statement $after of $operation';
            events.clear();
            capture
              ..reset()
              ..cancelAfter(
                after,
                TimeoutException(
                  'Request deadline exceeded',
                  const Duration(seconds: 5),
                ),
              );
            final body = await post(document, operation, _allIds);
            if (capture.cancelled) {
              // One error for the caller (or the answer, when the deadline
              // fired after the last statement).
              expect(body['errors'], anyOf(isNull, hasLength(1)), reason: at);
              if (body['errors'] != null) failedAtDeadline++;
            } else {
              // The whole batch took fewer statements and simply answered.
              expect(body['errors'], isNull, reason: at);
            }

            // The deadline is reported at most once, and never as a failed
            // rollback.
            final reported = [for (final event in events) event.throwable];
            expect(
              [
                ...reported,
                ...capture.errors,
              ].whereType<CouldNotRollBackException>(),
              isEmpty,
              reason: '$at. Reported: $reported',
            );
            expect(reported, hasLength(lessThanOrEqualTo(1)), reason: at);

            // Nothing of the cancelled request is left on the server.
            await _expectNoSessionInTransaction(session.writer, at);

            // The next request runs on the same (only) connection.
            events.clear();
            capture.reset();
            final recovered = await rows(document, operation, field, _allIds);
            expect(
              recovered.map((row) => row['beaconId']),
              operation == 'InboxRoomContextBatch'
                  ? _allIds
                  : _allIds.where(_readableIds.contains),
              reason: at,
            );
            expect(events, isEmpty, reason: at);
            expect(getIt<MainDbPool>().admission.running, 0, reason: at);
            expect(getIt<MainDbPool>().admission.queued, 0, reason: at);
          }
          expect(
            failedAtDeadline,
            greaterThan(0),
            reason: 'The deadline must interrupt $operation at least once.',
          );
        },
        skip: unavailable,
      );
    }
  });
}

String _notBatched(String operation, {required int many, required int few}) =>
    '$operation sent $many statements for $_requestCount Requests and $few '
    'for ${_fewIds.length}: the reads must be batched over the list, not '
    'repeated per Request';

Future<void> _expectNoSessionInTransaction(
  pg.Connection writer,
  String at,
) async {
  final clock = Stopwatch()..start();
  List<String> states;
  do {
    await writer.execute('SELECT pg_stat_clear_snapshot()');
    final rows = await writer.execute('''
      SELECT state FROM pg_stat_activity
      WHERE datname = current_database() AND pid <> pg_backend_pid()
        AND state LIKE 'idle in transaction%'
    ''');
    states = [for (final row in rows) row.single! as String];
    if (states.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  } while (clock.elapsed < const Duration(seconds: 2));
  fail('$at: the cancelled request left sessions $states');
}

/// What is wrong with the actual plan of one batch statement.
///
/// * No access to room messages examines more rows than twice what the
///   requested Requests hold: a scan over every room (the crowd included)
///   is not keyed by the list.
/// * No subquery runs more than once per requested Request.
Future<List<String>> _planViolations(
  pg.Connection writer,
  _Statement statement, {
  required int requested,
  required int requestedMessages,
}) async {
  final plan = await _explain(writer, statement);
  final violations = <String>[];
  for (final node in _nodes(plan)) {
    final relation = node['Relation Name'];
    final label =
        '${node['Node Type']}${relation == null ? '' : ' on $relation'}'
        '${node['Index Name'] == null ? '' : ' using ${node['Index Name']}'}';
    final loops = (node['Actual Loops']! as num).round();
    final examined =
        ((node['Actual Rows']! as num) +
                ((node['Rows Removed by Filter'] as num?) ?? 0) +
                ((node['Rows Removed by Index Recheck'] as num?) ?? 0))
            .round() *
        loops;
    if (relation == 'beacon_room_message' && examined > 2 * requestedMessages) {
      violations.add(
        '$label examines $examined room messages; the requested Requests '
        'hold $requestedMessages. Statement: ${statement.sql}',
      );
    }
    if (node['Parent Relationship'] == 'SubPlan' && loops > requested) {
      violations.add(
        '${node['Subplan Name']} ($label) runs $loops times; $requested '
        'Requests were asked for. Statement: ${statement.sql}',
      );
    }
  }
  return violations;
}

Future<Map<String, Object?>> _explain(
  pg.Connection writer,
  _Statement statement,
) async {
  await writer.execute('BEGIN');
  try {
    final result = await writer.execute(
      'EXPLAIN (ANALYZE, FORMAT JSON) ${statement.sql}',
      parameters: statement.arguments,
    );
    final value = result.single.single;
    final decoded = value is String ? jsonDecode(value) : value;
    return ((decoded! as List<Object?>).single!
            as Map<String, Object?>)['Plan']!
        as Map<String, Object?>;
  } finally {
    await writer.execute('ROLLBACK');
  }
}

Iterable<Map<String, Object?>> _nodes(Map<String, Object?> node) sync* {
  yield node;
  for (final child in (node['Plans'] as List<Object?>?) ?? const []) {
    yield* _nodes(child! as Map<String, Object?>);
  }
}

Future<void> _seed(pg.Connection writer) async {
  for (final (index, id) in [
    _viewer,
    _author,
    _helper,
    _crowdAuthor,
  ].indexed) {
    await writer.execute(
      pg.Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': pgTestPublicKey('requestlist', index + 1)},
    );
  }

  Future<void> requests(
    String prefix,
    int count,
    String authorId, {
    required bool published,
    bool discoverable = true,
  }) => writer.execute('''
    INSERT INTO public.beacon (
      id, user_id, title, description, status, published_at, is_discoverable
    )
    SELECT '$prefix' || lpad(n::text, 5, '0'), '$authorId',
           'Request ' || n, 'Request list batch fixture', 0,
           ${published ? "now() - interval '3 days'" : 'NULL'},
           $discoverable
    FROM generate_series(0, ${count - 1}) n
  ''');

  await requests('Bbatchown', _ownRequests, _viewer, published: true);
  await requests('Bbatchadm', _admittedRequests, _author, published: true);
  await requests('Bbatchpub', _publicRequests, _author, published: true);
  await requests('Bbatchhid', _hiddenRequests, _author, published: false);
  await requests('Bbatchcrd', _crowdRequests, _crowdAuthor, published: true);

  // The viewer reads [_author]'s public Requests because they were
  // forwarded to them; they are not in those rooms.
  await writer.execute('''
    INSERT INTO public.beacon_forward_edge
      (id, beacon_id, sender_id, recipient_id)
    SELECT 'Fbatch' || b.id, b.id, '$_author', '$_viewer'
    FROM public.beacon b
    WHERE b.id LIKE 'Bbatchpub%'
  ''');
  // The helper is admitted to every room; the viewer to [_author]'s
  // admitted Requests.
  await writer.execute('''
    INSERT INTO public.beacon_participant
      (id, beacon_id, user_id, role, status, room_access)
    SELECT 'Pbatchh' || b.id, b.id, '$_helper', 0, 0, 3
    FROM public.beacon b
    WHERE b.id LIKE 'Bbatchown%' OR b.id LIKE 'Bbatchadm%'
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_participant
      (id, beacon_id, user_id, role, status, room_access)
    SELECT 'Pbatchv' || b.id, b.id, '$_viewer', 0, 0, 3
    FROM public.beacon b
    WHERE b.id LIKE 'Bbatchadm%'
  ''');
  // An open help offer on each authored Request.
  await writer.execute('''
    INSERT INTO public.beacon_help_offer (beacon_id, user_id, status)
    SELECT b.id, '$_helper', 0
    FROM public.beacon b
    WHERE b.id LIKE 'Bbatchown%'
  ''');

  // Each room: [_seenMessages] read by the viewer, then [_unreadMessages]
  // newer ones by the helper.
  await writer.execute('''
    INSERT INTO public.beacon_room_message (beacon_id, author_id, body, created_at)
    SELECT b.id, '$_helper', 'Seen ' || m || ' in ' || b.id,
           now() - interval '2 days' + make_interval(mins => m)
    FROM public.beacon b
    CROSS JOIN generate_series(0, ${_seenMessages - 1}) m
    WHERE b.id LIKE 'Bbatchown%' OR b.id LIKE 'Bbatchadm%'
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_room_seen (user_id, beacon_id, last_seen_at)
    SELECT '$_viewer', b.id, now() - interval '1 day'
    FROM public.beacon b
    WHERE b.id LIKE 'Bbatchown%' OR b.id LIKE 'Bbatchadm%'
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_room_message (beacon_id, author_id, body, created_at)
    SELECT b.id, '$_helper', 'Unread ' || m || ' in ' || b.id,
           now() - interval '1 hour' + make_interval(mins => m)
    FROM public.beacon b
    CROSS JOIN generate_series(0, ${_unreadMessages - 1}) m
    WHERE b.id LIKE 'Bbatchown%' OR b.id LIKE 'Bbatchadm%'
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_room_message (beacon_id, author_id, body, created_at)
    SELECT b.id, '$_crowdAuthor', 'Crowd ' || m,
           now() - interval '3 days' + make_interval(mins => m)
    FROM public.beacon b
    CROSS JOIN generate_series(0, ${_crowdMessagesPerRequest - 1}) m
    WHERE b.id LIKE 'Bbatchcrd%'
  ''');

  for (final table in [
    'beacon',
    'beacon_participant',
    'beacon_help_offer',
    'beacon_room_message',
    'beacon_room_seen',
    'beacon_forward_edge',
  ]) {
    await writer.execute('ANALYZE public.$table');
  }
}

final class _Statement {
  _Statement(this.sql, this.arguments);
  final String sql;
  final List<Object?> arguments;
}

/// Records every SELECT the repositories send through a leased scope, so
/// the test can count and replay the production statements as issued; can
/// cancel the running request after a given number of them, as its
/// deadline timer would.
final class _StatementCapture extends QueryInterceptor {
  final statements = <_Statement>[];
  final errors = <Object>[];
  int? _cancelAfter;
  Object? _cancelReason;
  bool cancelled = false;
  RequestContext? _request;

  void reset() {
    statements.clear();
    errors.clear();
    _cancelAfter = null;
    _cancelReason = null;
    cancelled = false;
  }

  void cancelAfter(int count, Object reason) {
    _cancelAfter = count;
    _cancelReason = reason;
  }

  Future<T> duringRequest<T>(Future<T> Function() action) async {
    _request = RequestContext.current;
    try {
      return await action();
    } finally {
      _request = null;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    statements.add(_Statement(statement, List.of(args)));
    try {
      return await executor.runSelect(statement, args);
    } on Object catch (error) {
      errors.add(error);
      rethrow;
    } finally {
      final after = _cancelAfter;
      if (after != null && !cancelled && statements.length >= after) {
        cancelled = true;
        _request?.cancel(_cancelReason);
      }
    }
  }
}
