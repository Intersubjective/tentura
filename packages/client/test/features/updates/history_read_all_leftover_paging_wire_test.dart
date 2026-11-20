@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';

import '../../support/attention_case_factory.dart';
import '../../domain/attention/attention_case_test_support.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/production_receipt_transport.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

// «Read all» in History with a followed forwarded Request whose old receipt an
// earlier Read all left seen-but-uncleared, behind 59 newer unread items (two
// 50-item pages). Real path:
// production GraphQL server on Postgres -> Ferry -> repository -> case ->
// cubit -> tiles. A reload is a new case and cubit over the same server
// state. Browser page-reload behaviour needs the web integration runner.
const _viewer = 'Ua00000000005';
const _forwardId = 'Nfwdrelay00001';

Future<void> _until(bool Function() ready, {Object? Function()? why}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out: ${why?.call()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A History cubit over its own [AttentionCase], like a freshly opened app.
final class _Session {
  _Session._(
    this.remote,
    this.repository,
    this.accounts,
    this.sync,
    this.attention,
    this.cubit,
  );

  final RemoteApiService remote;
  final AttentionRepository repository;
  final AttentionCaseTestAccounts accounts;
  final ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  final AttentionCase attention;
  final UpdatesFeedCubit cubit;

  static Future<_Session> open() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    await remote.setSessionAuth();
    final repository = AttentionRepository(remote);
    final accounts = AttentionCaseTestAccounts();
    final sync = buildTestRealtimeSync();
    final attention = buildAttentionCase(
      repository: repository,
      accounts: accounts,
      realtimeSyncCase: sync.case_,
      blockCase: noopBlockCase(),
      feedSessions: FeedSessionRegistry(),
      logger: Logger('history-read-all-forward'),
    );
    accounts.emit(_viewer);
    await Future<void>.delayed(Duration.zero);
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.history,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('history-read-all-forward-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    await _until(() => cubit.state.firstLoadDone, why: () => 'History load');
    return _Session._(remote, repository, accounts, sync, attention, cubit);
  }

  Future<void> close() async {
    await cubit.close();
    await attention.dispose();
    await sync.port.dispose();
    await accounts.dispose();
    await remote.close();
  }
}

Future<void> _withServer(
  WidgetTester tester,
  Future<void> Function() body,
) =>
    tester.runAsync(() async {
          final transport = await ProductionReceiptTransport.start(
            leftoverForwardRequestFixture: true,
          );
          try {
            await http.runWithClient(
              body,
              () => MockClient((request) async {
                if (request.url.path.endsWith('/session/access-token')) {
                  return http.Response(
                    jsonEncode({
                      'subject': _viewer,
                      'access_token': 'test-token',
                      'expires_in': 3600,
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                return transport.graphql(
                  _viewer,
                  jsonDecode(request.body) as Map<String, dynamic>,
                );
              }),
            );
          } finally {
            await transport.close();
          }
        })
        as Future<void>;

/// Every receipt the Unread view lists, following the next-page cursor.
Future<(List<String> ids, int pages)> _unreadViewPages(
  AttentionRepository repository,
) async {
  final ids = <String>[];
  String? cursor;
  var pages = 0;
  do {
    final feed = await repository.fetch(
      view: AttentionView.unread,
      cursor: cursor,
    );
    ids.addAll(feed.page.items.map((r) => r.id));
    cursor = feed.page.nextCursor;
    pages++;
  } while (cursor != null && pages < 10);
  return (ids, pages);
}

/// The old forwarded-Request receipt, wherever it sits in History (it is
/// beyond the first 50 items), is listed and read.
Future<void> _expectForwardReceiptRead(AttentionRepository repository) async {
  String? cursor;
  var pages = 0;
  final found = <AttentionReceipt>[];
  do {
    final feed = await repository.fetch(
      view: AttentionView.all,
      cursor: cursor,
    );
    found.addAll(feed.page.items.where((r) => r.id == _forwardId));
    cursor = feed.page.nextCursor;
    pages++;
  } while (cursor != null && pages < 10);
  expect(found, hasLength(1), reason: 'old forward receipt is listed');
  expect(found.single.isSeen, isTrue, reason: 'old forward receipt is read');
}

void main() {
  testWidgets(
    'Read all over a history longer than one page leaves the old followed '
    'forwarded-Request receipt read, both Unread pages empty, and the count '
    '0 on a fresh fetch',
    (tester) async {
      await _withServer(tester, () async {
        final session = await _Session.open();
        try {
          final before = await session.repository.fetch(
            view: AttentionView.unread,
          );
          expect(before.summary.unreadTotal, 60, reason: 'precondition');
          expect(before.page.nextCursor, isNotNull, reason: 'two pages');

          expect(await session.cubit.markAllSeen(), isTrue);
          await _until(
            () => session.cubit.state.summary.unreadTotal == 0,
            why: () => session.cubit.state.summary,
          );
          expect(session.cubit.state.canReadAll, isFalse);

          expect(
            (await session.repository.fetch(
              view: AttentionView.unread,
            )).summary.unreadTotal,
            0,
          );
          final (ids, _) = await _unreadViewPages(session.repository);
          expect(ids, isEmpty, reason: 'no page of Unread lists anything');

          await session.attention.refresh();
          final fresh = await session.repository.fetch(view: AttentionView.all);
          expect(fresh.summary.unreadTotal, 0, reason: 'fresh fetch');
          await _expectForwardReceiptRead(session.repository);
        } finally {
          await session.close();
        }
      });
    },
  );

  testWidgets(
    'the History screen cubit shows nothing unread after Read all and after '
    'a reload over the same server state',
    (tester) async {
      await _withServer(tester, () async {
        final first = await _Session.open();
        try {
          expect(first.cubit.state.summary.unreadTotal, 60);
          expect(await first.cubit.markAllSeen(), isTrue);
          await _until(
            () => first.cubit.state.summary.unreadTotal == 0,
            why: () => first.cubit.state.summary,
          );
        } finally {
          await first.close();
        }

        final reloaded = await _Session.open();
        try {
          await _until(
            () => reloaded.cubit.state.summary.unreadTotal == 0,
            why: () => reloaded.cubit.state.summary,
          );
          expect(reloaded.cubit.state.canReadAll, isFalse);
          expect(
            reloaded.cubit.state.items.where((r) => !r.isSeen),
            isEmpty,
          );
          // The old receipt sits on History's second page, beyond the
          // cubit's first load.
          await _expectForwardReceiptRead(reloaded.repository);
        } finally {
          await reloaded.close();
        }
      });
    },
  );
}
