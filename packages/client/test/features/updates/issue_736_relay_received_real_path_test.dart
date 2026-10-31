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

// #736 round 4 (QA 2026-10-31, 7.59.40): a forwarded Request showed in the
// recipient's Updates as «Q1031 Alice» and nothing else — the server titles
// `relay_received` with the sender's name only and the row kept it as the
// headline. Real path: the wire receipt as the server stores it → Ferry →
// AttentionRepository → AttentionCase → UpdatesFeedCubit → the Updates row.

const _sender = 'Q1031 Alice';
const _request = 'QA1031 R2 two';
const _note = 'q1031 forward';

Map<String, dynamic> _wireRelayReceipt() => {
  '__typename': 'AttentionReceipt',
  'id': 'Nrelay000000001',
  'category': 'requestProgress',
  'kind': 'newRelay',
  'priority': 'low',
  // BeaconNotificationCopyBuilder (newRelay): title = actor, body =
  // «actor: note».
  'title': _sender,
  'body': '$_sender: $_note',
  'actionUrl': '/#/beacon/view/Be80948436804',
  'createdAt': '2026-10-31T00:10:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': 'Be80948436804',
  'coordinationItemId': null,
  'actorUserId': 'Ualice000000001',
  'sourceEventKey': 'relayReceived:Be80948436804:Udave0000000001',
  'destinationKind': 'beacon',
  'targetEntityId': null,
  'presentationKey': 'relay_received',
  // AttentionPolicy._presentationPayload for relayReceived.
  'presentationPayloadJson': jsonEncode({
    'eventType': 'relayReceived',
    'personal': true,
    'actorUserId': 'Ualice000000001',
    'beaconId': 'Be80948436804',
    'beaconTitle': _request,
    'excerpt': _note,
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
};

/// The receipt as the real repository maps it from the wire.
Future<AttentionReceipt> _mappedReceipt() async {
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
          'items': [_wireRelayReceipt()],
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

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == text,
      ),
    );

void main() {
  for (final (locale, size, headline, body) in [
    (
      const Locale('en'),
      const Size(800, 800),
      '$_sender forwarded a request to you',
      '$_request — “$_note”',
    ),
    (
      const Locale('ru'),
      const Size(375, 667),
      '$_sender переслал(а) вам запрос',
      '$_request — «$_note»',
    ),
  ]) {
    testWidgets(
      '${locale.languageCode} ${size.width.toInt()}x${size.height.toInt()}: '
      'a forward says who forwarded it, with the Request and the note',
      (tester) async {
        late AttentionReceipt receipt;
        await tester.runAsync(() async => receipt = await _mappedReceipt());
        expect(receipt.presentationKey, 'relay_received');

        final server = MarkUnreadServerFake([receipt]);
        final accounts = _Accounts();
        final sync = buildTestRealtimeSync();
        final attention = AttentionCase(
          server,
          accounts,
          sync.case_,
          noopBlockCase(),
          FeedSessionRegistry(),
          Logger('issue-736-relay'),
        );
        final cubit = UpdatesFeedCubit(
          destinationId: AttentionFeedDestinationId.activityStream,
          attention: attention,
          setup: NoopInviteAcceptedSetupPort(),
          realtime: sync.case_,
          logger: Logger('issue-736-relay-cubit'),
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
        // The headline says what happened, whole — not the bare name.
        expect(
          find.descendant(
            of: row,
            matching: find.text(headline, findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.text(_sender, findRichText: true),
          ),
          findsNothing,
        );
        expect(_paragraph(tester, headline).didExceedMaxLines, isFalse);
        // The body keeps the Request title and the forward note.
        expect(
          find.descendant(
            of: row,
            matching: find.text(body, findRichText: true),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        unawaited(cubit.close());
        unawaited(attention.dispose());
        unawaited(sync.port.dispose());
        unawaited(accounts.close());
      },
    );
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
