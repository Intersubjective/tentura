import 'dart:async';
import 'dart:convert';

import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import 'support/mark_unread_server_fake.dart';
import 'support/noop_invite_setup_port.dart';

// Updates rows built from real wire receipts carry the names and facts the
// event needs: the linked Request's title, the message text, a formatted
// deadline, quiet days with the Russian plural, the person in a trust change.
// The receipt goes through Ferry → AttentionRepository → AttentionCase →
// UpdatesFeedCubit → UpdatesFeedTile, on desktop in EN and at 375x667 in RU,
// where the visible line must also fit without truncation.

const _request = 'Fix the roof';

/// One receipt in the shape the server sends (`AttentionReceiptFields`),
/// with the facts the new copy needs in the payload.
Map<String, dynamic> _wire({
  required String presentationKey,
  required Map<String, Object?> payload,
  String? relatedBeaconTitle,
}) => {
  '__typename': 'AttentionReceipt',
  'id': 'Ncopy000000001',
  'category': 'requestProgress',
  'kind': 'roomActivityLowPriority',
  'priority': 'low',
  'title': 'Anna',
  'body': '',
  'actionUrl': '/#/beacon/view/Be80948436804',
  'createdAt': '2026-10-31T00:10:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': 'Be80948436804',
  'coordinationItemId': null,
  'actorUserId': 'Uanna000000001',
  'sourceEventKey': 'copy:$presentationKey',
  'destinationKind': 'beacon',
  'targetEntityId': null,
  'presentationKey': presentationKey,
  'presentationPayloadJson': jsonEncode({
    'personal': true,
    'actorUserId': 'Uanna000000001',
    'actorName': 'Anna',
    'beaconId': 'Be80948436804',
    'beaconTitle': _request,
    ...payload,
  }),
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'surface': 'activity',
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'beaconTitle': _request,
  'relatedBeaconTitle': ?relatedBeaconTitle,
};

Future<AttentionReceipt> _mappedReceipt(Map<String, dynamic> wire) async {
  final remote = _FixtureRemoteClient()
    ..data = GAttentionFeedData.fromJson({
      '__typename': 'query_root',
      'attentionFeed': {
        '__typename': 'AttentionFeed',
        'summary': {
          '__typename': 'AttentionSummary',
          'unreadTotal': 1,
          'needsYouTotal': 0,
        },
        'page': {
          '__typename': 'AttentionPage',
          'nextCursor': null,
          'items': [wire],
        },
      },
    });
  final feed = await AttentionRepository(
    remote,
  ).fetch(view: AttentionView.all);
  return feed.page.items.single;
}

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

// Real path: the wire receipt as the server sends it (including the access-
// gated `relatedBeaconTitle`) → Ferry → AttentionRepository → AttentionCase →
// UpdatesFeedCubit → the Updates row, in EN on desktop and in RU at 375x667.

typedef _Case = ({
  String name,
  Map<String, dynamic> wire,
  Map<Locale, (Size, List<String>)> expected,
  List<String> absent,
  bool requestTitleAtMostOnce,
});

final _cases = <_Case>[
  (
    name: 'a linked Request status names the linked Request',
    wire: _wire(
      presentationKey: 'beacon_hierarchy_status_changed',
      payload: {
        'eventType': 'beaconHierarchyStatusChanged',
        'toStatus': 'closed',
      },
      relatedBeaconTitle: 'Buy paint',
    ),
    expected: {
      const Locale('en'): (
        const Size(800, 800),
        ['Linked request «Buy paint» was closed'],
      ),
      const Locale('ru'): (
        const Size(375, 667),
        ['Связанный запрос «Buy paint» закрыт'],
      ),
    },
    absent: ['Linked request status changed', 'Статус связанного запроса'],
    requestTitleAtMostOnce: false,
  ),
  (
    name: 'a room message shows its text and not the Request title as body',
    wire: _wire(
      presentationKey: 'room_message_posted',
      payload: {'eventType': 'roomMessagePosted', 'excerpt': 'Bring a ladder'},
    ),
    expected: {
      const Locale('ru'): (const Size(375, 667), ['Bring a ladder']),
    },
    absent: [],
    requestTitleAtMostOnce: true,
  ),
  (
    name: 'a deadline change names the person and the formatted date',
    wire: _wire(
      presentationKey: 'deadline_changed',
      payload: {
        'eventType': 'deadlineChanged',
        'newEndAt': DateTime(DateTime.now().year, 11, 21, 18).toIso8601String(),
      },
    ),
    expected: {
      const Locale('ru'): (
        const Size(375, 667),
        ['Anna: новый срок — 21 ноября, 18:00'],
      ),
    },
    absent: ['T18:00', '-11-21'],
    requestTitleAtMostOnce: false,
  ),
  (
    name: 'a quiet Request says how many days in Russian plural',
    wire: _wire(
      presentationKey: 'request_stale',
      payload: {
        'eventType': 'requestStale',
        'staleReason': 'quiet',
        'quietDays': 5,
      },
    ),
    expected: {
      const Locale('ru'): (
        const Size(375, 667),
        ['5 дней без движения. Закройте, продлите или напишите новости'],
      ),
    },
    absent: [],
    requestTitleAtMostOnce: false,
  ),
  (
    name: 'a trust change names the person',
    wire: _wire(
      presentationKey: 'trust_received_changed_up',
      payload: {'eventType': 'trustReceivedChanged'},
    ),
    expected: {
      const Locale('ru'): (const Size(375, 667), ['Anna доверяет вам больше']),
    },
    absent: [],
    requestTitleAtMostOnce: false,
  ),
];

void main() {
  for (final c in _cases) {
    c.expected.forEach((locale, spec) {
      final (size, texts) = spec;
      testWidgets(
        '${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()}: '
        '${c.name}',
        (tester) async {
          late AttentionReceipt receipt;
          await tester.runAsync(
            () async => receipt = await _mappedReceipt(c.wire),
          );
          final server = MarkUnreadServerFake([receipt]);
          final accounts = _Accounts();
          final sync = buildTestRealtimeSync();
          final attention = AttentionCase(
            server,
            accounts,
            sync.case_,
            noopBlockCase(),
            FeedSessionRegistry(),
            Logger('updates-row-copy-real-path'),
          );
          final cubit = UpdatesFeedCubit(
            destinationId: AttentionFeedDestinationId.activityStream,
            attention: attention,
            setup: NoopInviteAcceptedSetupPort(),
            realtime: sync.case_,
            logger: Logger('updates-row-copy-real-path-cubit'),
            actorProfiles: buildNoopAttentionActorProfiles(),
          );
          accounts.emit('viewer');
          await _drain();

          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(size: size),
              child: TenturaResponsiveScope(
                child: MaterialApp(
                  locale: locale,
                  theme: TenturaTheme.light(),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: Scaffold(
                    body: BlocProvider.value(
                      value: cubit,
                      child: const UpdatesFeedPane(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          await _drain();
          await tester.pumpAndSettle();

          final row = find.byType(UpdatesFeedTile);
          expect(row, findsOneWidget);
          for (final text in texts) {
            final hit = find.descendant(
              of: row,
              matching: find.textContaining(text, findRichText: true),
            );
            expect(hit, findsOneWidget, reason: text);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: row,
                matching: find.byWidgetPredicate(
                  (w) => w is RichText && w.text.toPlainText().contains(text),
                ),
              ),
            );
            expect(paragraph.didExceedMaxLines, isFalse, reason: text);
          }
          if (c.requestTitleAtMostOnce) {
            expect(
              find
                  .descendant(
                    of: row,
                    matching: find.textContaining(_request, findRichText: true),
                  )
                  .evaluate()
                  .length,
              lessThanOrEqualTo(1),
              reason: 'the Request title is the tile line, not the body',
            );
          }
          for (final text in c.absent) {
            expect(
              find.descendant(
                of: row,
                matching: find.textContaining(text, findRichText: true),
              ),
              findsNothing,
              reason: text,
            );
          }
          expect(tester.takeException(), isNull);

          unawaited(cubit.close());
          unawaited(attention.dispose());
          unawaited(sync.port.dispose());
          unawaited(accounts.close());
        },
      );
    });
  }
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _FixtureRemoteClient implements RemoteRequestClient {
  GAttentionFeedData? data;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    if (request is GAttentionFeedReq) {
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: data as TData,
        ),
      );
    }
    throw UnsupportedError('Unexpected operation: $request');
  }
}
