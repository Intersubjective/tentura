import 'dart:convert';

import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/updates/ui/widget/updates_receipt_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/russian_closed_request_copy.dart';

const _en = Locale('en');
const _ru = Locale('ru');
const _inviter = 'Vadim';
const _request = 'Fix the roof';
const _actorId = 'U000000000001';
const _closed =
    'Vadim invited you to «Fix the roof», but it has already closed.';
const _welcome =
    "You're still welcome on Tentura, and you're now connected with Vadim.";

void main() {
  testWidgets(
    'connection cards explain that the invited Request closed when applicable',
    (
      tester,
    ) async {
      await _showConnection(tester, locale: _en);
      expect(
        _cardText(
          find.text(lookupL10n(_en).updatesMutualConnectionHeadline(_inviter)),
        ),
        findsOneWidget,
      );
      expect(
        _cardText(find.textContaining('has already closed')),
        findsNothing,
      );
      expect(_cardText(find.textContaining(_request)), findsNothing);

      await _showConnection(tester, locale: _en, lapsedRequestTitle: _request);
      _expectPublicCopy();
      expect(
        _cardText(find.text('$_closed $_welcome', findRichText: true)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a new connection card names the inviter and closed Request in Russian on a phone',
    (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _showConnection(tester, locale: _ru, lapsedRequestTitle: _request);

      _expectPublicCopy();
      expect(
        _cardText(find.textContaining(_closed, findRichText: true)),
        findsNothing,
      );
      expect(
        _cardText(find.textContaining(_welcome, findRichText: true)),
        findsNothing,
      );
      final copy = _cardText(
        findRussianClosedRequestCopy(
          inviter: _inviter,
          title: _request,
          welcomesNewAccount: true,
        ),
      );
      expect(
        copy,
        findsOneWidget,
        reason: 'Expected Russian copy explaining the closure and connection.',
      );
      expect(
        tester.renderObject<RenderParagraph>(copy).didExceedMaxLines,
        isFalse,
      );
    },
  );
}

Finder _cardText(Finder matching) =>
    find.descendant(of: find.byType(UpdatesReceiptCard), matching: matching);

void _expectPublicCopy() {
  expect(
    _cardText(
      find.textContaining(
        RegExp('phantom|фантом', caseSensitive: false),
        findRichText: true,
      ),
    ),
    findsNothing,
  );
}

Future<void> _showConnection(
  WidgetTester tester, {
  required Locale locale,
  String? lapsedRequestTitle,
}) async {
  const connectedBody = 'You and Vadim are now connected.';
  final wireReceipt = {
    '__typename': 'AttentionReceipt',
    'id': 'N000000000001',
    'category': 'connections',
    'kind': 'inviteAccepted',
    'priority': 'normal',
    'title': 'New connection',
    'body': lapsedRequestTitle == null
        ? connectedBody
        : '$connectedBody The Request «$lapsedRequestTitle» is no longer '
              'available through this invitation.',
    'actionUrl': '/#/profile/view/$_actorId',
    'createdAt': '2026-10-31T00:10:00.000Z',
    'collapsedCount': 1,
    'actorUserId': _actorId,
    'sourceEventKey': 'connection:$_actorId',
    'destinationKind': 'profile',
    'targetEntityId': _actorId,
    'presentationKey': 'mutual_connection_formed',
    'presentationPayloadJson': jsonEncode({
      'eventType': 'mutualConnectionFormed',
      'personal': false,
      'actorUserId': _actorId,
      'targetEntityId': _actorId,
      'actorName': _inviter,
      'lapsedRequestTitle': ?lapsedRequestTitle,
    }),
    'requiresAction': false,
    'surface': 'activity',
    'itemKind': 'receipt',
  };
  final remote = _ReceiptRemote(
    GAttentionFeedData.fromJson({
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
          'items': [wireReceipt],
        },
      },
    })!,
  );
  final feed = await tester.runAsync(
    () => AttentionRepository(remote).fetch(view: AttentionView.all),
  );

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: UpdatesReceiptCard(
            receipt: feed!.page.items.single,
            onTap: () {},
            onMarkSeen: () {},
            onMarkUnseen: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

final class _ReceiptRemote implements RemoteRequestClient {
  _ReceiptRemote(this.data);

  final GAttentionFeedData data;

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
