@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_attention.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/forward_request_receipt_fixture.dart';

const _closeId = 'inbox:$forwardRequestBeaconId';
const _otherViewer = 'Ua00000000004';

GraphQL _historyApi(TenturaDb database) {
  final queries = QueryAttention(query: AttentionRepository(database));
  final mutations = MutationAttention(ack: AttentionAckRepository(database));
  return GraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('Query', null)
        ..fields.addAll([
          queries.attentionFeed,
          queries.attentionSurfaceSummary,
        ]),
      mutationType: GraphQLObjectType('Mutation', null)
        ..fields.addAll([
          mutations.attentionMarkAllSeen,
          mutations.attentionMarkSeen,
          mutations.attentionMarkUnseen,
          mutations.attentionMarkUnread,
        ]),
    ),
  );
}

Future<Map<String, dynamic>> _execute(
  GraphQL api,
  String document, {
  String viewer = forwardRequestViewerId,
}) async =>
    (await api.parseAndExecute(
              document,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
            )
            as Map)
        .cast<String, dynamic>();

Future<int> _mark(
  GraphQL api,
  String mutation, {
  String viewer = forwardRequestViewerId,
}) async =>
    (await _execute(
          api,
          'mutation { $mutation(ids: ["$_closeId"]) }',
          viewer: viewer,
        ))[mutation]
        as int;

Future<({Map<dynamic, dynamic> card, bool inUnread, int unreadTotal})> _history(
  GraphQL api,
) async {
  // The History pane leaves the surface filter unset to select the account-wide
  // History projection. The named surfaces filter My Work or select Activity.
  final data = await _execute(api, '''
{
  all: attentionFeed(view: "all") {
    page { items { id seenAt clearedAt forwardOutcome } }
  }
  unread: attentionFeed(view: "unread") {
    page { items { id } }
  }
  attentionSurfaceSummary { unreadTotal }
}
''');
  List<Map<dynamic, dynamic>> rows(String view) =>
      (((data[view] as Map)['page'] as Map)['items'] as List)
          .cast<Map<dynamic, dynamic>>();
  final closeCardsInAll = rows('all').where((row) => row['id'] == _closeId);
  expect(
    closeCardsInAll,
    hasLength(1),
    reason: 'History All keeps the close card in either read state',
  );
  return (
    card: closeCardsInAll.single,
    inUnread: rows('unread').any((row) => row['id'] == _closeId),
    unreadTotal: (data['attentionSurfaceSummary'] as Map)['unreadTotal'] as int,
  );
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HISTORY_CLOSED_FORWARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_hist_closed_forward',
  );
  final skipReason = await pgSkipReason(target);

  group('History card for a Request closed before the viewer answered', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late GraphQL api;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      database = openDisposablePgDatabase(target);
      api = _historyApi(database);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() async {
      final writer = session.writer;
      await writer.execute('TRUNCATE public."user", public.beacon CASCADE');
      for (final id in [
        forwardRequestAuthorId,
        forwardRequestViewerId,
        _otherViewer,
      ]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await seedForwardRequestHistory(writer);
      final readAll = await _execute(api, 'mutation { attentionMarkAllSeen }');
      expect(readAll['attentionMarkAllSeen'], greaterThan(0));
      final openHistory = await _execute(api, '''
{
  attentionFeed(view: "all") { page { items { id seenAt clearedAt } } }
}
''');
      final page = (openHistory['attentionFeed'] as Map)['page'] as Map;
      final relay = (page['items'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (row) => row['id'] == forwardRequestReceiptId,
          );
      expect(relay['seenAt'], isNotNull);
      expect(relay['clearedAt'], isNotNull);
      await database.withMutatingUser(
        forwardRequestAuthorId,
        () => BeaconRepository(database).recordBeaconStatusTransition(
          beaconId: forwardRequestBeaconId,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.closed,
          reason: BeaconLifecycleChangeReason.directClose,
          actorId: forwardRequestAuthorId,
        ),
      );
    });

    for (final (mutation, description) in [
      ('attentionMarkUnseen', 'Mark unread'),
      ('attentionMarkUnread', 'restore to Unread'),
    ]) {
      test(
        '$description returns the read card to Unread for its viewer only',
        () async {
          final initial = await _history(api);
          expect(initial.card['forwardOutcome'], 'closedBeforeResponse');
          expect(initial.card['clearedAt'], isNull);
          expect(initial.card['seenAt'], isNull);
          expect(initial.inUnread, isTrue);

          expect(await _mark(api, 'attentionMarkSeen'), greaterThan(0));
          final read = await _history(api);
          expect(read.card['seenAt'], isNotNull);
          expect(read.inUnread, isFalse);
          expect(read.unreadTotal, initial.unreadTotal - 1);

          expect(await _mark(api, mutation, viewer: _otherViewer), 0);
          final afterOtherViewer = await _history(api);
          expect(afterOtherViewer.card['seenAt'], isNotNull);
          expect(afterOtherViewer.inUnread, isFalse);
          expect(afterOtherViewer.unreadTotal, read.unreadTotal);

          final updated = await _mark(api, mutation);
          final fresh = openDisposablePgDatabase(target);
          try {
            final freshApi = _historyApi(fresh);
            final unread = await _history(freshApi);
            final markedSeen = await _mark(freshApi, 'attentionMarkSeen');
            final readAgain = await _history(api);
            expect(
              {
                'rows marked unread': updated,
                'fresh History seenAt': unread.card['seenAt'],
                'fresh History lists the card in Unread': unread.inUnread,
                'fresh History unread total': unread.unreadTotal,
                'rows marked read again': markedSeen,
                'History seenAt after marking read again':
                    readAgain.card['seenAt'],
                'History lists the card in Unread after marking read again':
                    readAgain.inUnread,
              },
              {
                'rows marked unread': greaterThan(0),
                'fresh History seenAt': isNull,
                'fresh History lists the card in Unread': true,
                'fresh History unread total': initial.unreadTotal,
                'rows marked read again': greaterThan(0),
                'History seenAt after marking read again': isNotNull,
                'History lists the card in Unread after marking read again':
                    false,
              },
            );
          } finally {
            await fresh.close();
          }
        },
      );
    }
  }, skip: skipReason);
}
