@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_actor_ids.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card_mapper.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/production_receipt_transport.dart';

const _anna = Profile(id: 'Ubaton0000001', displayName: 'Anna');
const _boris = Profile(id: 'Ubaton0000003', displayName: 'Boris');
const _carol = Profile(id: 'Ubaton0000002', displayName: 'Carol');
const _actors = {
  'Ubaton0000001': _anna,
  'Ubaton0000003': _boris,
  'Ubaton0000002': _carol,
};

const _joined = 'BbatonJoined1';
const _pairWithExcerpt = 'BbatonPairAsk';
const _declined = 'BbatonDecline';
const _noExcerptPair = 'BbatonNoQuote';
const _noExcerptSolo = 'BbatonSolo001';
const _answered = 'baton_partner_answered';
const _declinedEn = "Carol can't join you. Answer again";
const _declinedRu = 'Carol не сможет присоединиться. Ответьте ещё раз';
const _taken = 'baton_taken';

typedef _Case = ({
  String label,
  String request,
  Profile viewer,
  String key,
  String en,
  String ru,
});

const _cases = <_Case>[
  (
    label: 'joined',
    request: _joined,
    viewer: _boris,
    key: _answered,
    en: 'Carol will take it on with you',
    ru: 'Carol возьмётся вместе с вами',
  ),
  (
    label: 'declined',
    request: _declined,
    viewer: _boris,
    key: _answered,
    en: _declinedEn,
    ru: _declinedRu,
  ),
  (
    label: 'pair with ask text, first taker',
    request: _pairWithExcerpt,
    viewer: _boris,
    key: _taken,
    en: 'You and Carol took it: Bring chairs',
    ru: 'Вы и Carol взялись: Bring chairs',
  ),
  (
    label: 'pair with ask text, second taker',
    request: _pairWithExcerpt,
    viewer: _carol,
    key: _taken,
    en: 'You and Boris took it: Bring chairs',
    ru: 'Вы и Boris взялись: Bring chairs',
  ),
  (
    label: 'pair without ask text, first taker',
    request: _noExcerptPair,
    viewer: _boris,
    key: _taken,
    en: 'You and Carol took it.',
    ru: 'Вы взялись. Вместе с вами: Carol.',
  ),
  (
    label: 'pair without ask text, second taker',
    request: _noExcerptPair,
    viewer: _carol,
    key: _taken,
    en: 'You and Boris took it.',
    ru: 'Вы взялись. Вместе с вами: Boris.',
  ),
  (
    label: 'one taker without ask text',
    request: _noExcerptSolo,
    viewer: _boris,
    key: _taken,
    en: 'You took it.',
    ru: 'Вы взялись за это.',
  ),
];

Future<
  ({
    AttentionReceipt request,
    AttentionReceipt activity,
    AttentionReceipt? refetched,
  })
>
_read(
  ProductionReceiptTransport transport,
  _Case scenario,
) => http.runWithClient(
  () async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    try {
      await remote.setSessionAuth();
      final repository = AttentionRepository(remote);
      AttentionReceipt select(List<AttentionReceipt> receipts) => receipts
          .singleWhere((receipt) => receipt.presentationKey == scenario.key);
      final request = await repository.requestHistory(
        beaconId: scenario.request,
      );
      final activity = await repository.fetch(
        view: AttentionView.all,
        surface: AttentionSurface.activity,
      );
      return (
        request: select(request.items),
        activity: activity.page.items.singleWhere(
          (row) =>
              row.beaconId == scenario.request &&
              row.eventsPreview.any(
                (event) => event.presentationKey == scenario.key,
              ),
        ),
        refetched: scenario.key == _answered && scenario.request == _joined
            ? select(
                (await repository.requestHistory(
                  beaconId: scenario.request,
                )).items,
              )
            : null,
      );
    } finally {
      await remote.close();
    }
  },
  () => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': scenario.viewer.id,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return transport.graphql(
      scenario.viewer.id,
      jsonDecode(request.body) as Map<String, dynamic>,
    );
  }),
);

void _expectFlexChildrenFit(WidgetTester tester, Finder row, String label) {
  final flexes = find.descendant(
    of: row,
    matching: find.byWidgetPredicate((widget) => widget is Flex),
  );
  for (final flex in tester.renderObjectList<RenderFlex>(flexes)) {
    final bounds = (Offset.zero & flex.size).inflate(0.01);
    for (
      var child = flex.firstChild;
      child != null;
      child = flex.childAfter(child)
    ) {
      final data = child.parentData! as FlexParentData;
      final childBounds = data.offset & child.size;
      expect(
        bounds.intersect(childBounds),
        childBounds,
        reason: '$label must fit every ${flex.direction.name} RenderFlex child',
      );
    }
  }
}

bool _textFits(RenderParagraph paragraph, String text, Rect visibleBounds) {
  if (paragraph.didExceedMaxLines) return false;
  if (text.trim().isEmpty) return true;

  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  final transform = paragraph.getTransformTo(null);
  return boxes.isNotEmpty &&
      boxes.every((box) {
        final bounds = MatrixUtils.transformRect(transform, box.toRect());
        return visibleBounds.intersect(bounds) == bounds;
      });
}

Future<List<String>> _render(
  WidgetTester tester,
  Locale locale,
  Widget row, {
  required String label,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(child: Scaffold(body: row)),
    ),
  );
  await tester.pump();
  expect(
    tester.takeException(),
    isNull,
    reason: '$label must lay out and paint without exceptions',
  );
  final card = find.byWidget(row);
  expect(card, findsOneWidget);
  final Rect? visibleBounds;
  if (locale.languageCode == 'ru') {
    expect(tester.getSize(find.byType(Scaffold)), kPhoneSurface);
    _expectFlexChildrenFit(tester, card, label);
    visibleBounds = tester
        .getRect(card)
        .intersect(Offset.zero & kPhoneSurface)
        .inflate(0.01);
  } else {
    visibleBounds = null;
  }

  final lines = find.descendant(of: card, matching: find.byType(RichText));
  return lines.evaluate().map((element) {
    final text = (element.widget as RichText).text.toPlainText();
    final paragraph = element.renderObject! as RenderParagraph;
    final visible = visibleBounds == null
        ? !paragraph.didExceedMaxLines
        : _textFits(paragraph, text, visibleBounds);
    return visible ? text : '[clipped] $text';
  }).toList();
}

AttentionMiniCard _requestRow(AttentionReceipt receipt) => AttentionMiniCard(
  receipt: receipt,
  actor: _actors[receipt.actorUserId],
  partnerName:
      _actors[batonPartnerUserId(receipt.presentationPayloadJson)]?.displayName,
);

RequestAttentionCard _activityRow(AttentionReceipt row, String viewer) {
  final model = requestCardFromReceipt(row)!;
  return RequestAttentionCard(
    beacon: model.beacon,
    facts: model.facts,
    variant: model.variant,
    relation: model.relation,
    provenance: model.provenance,
    representative: model.representative,
    eventTotal: model.eventTotal,
    eventsPreview: model.eventsPreview,
    actors: _actors,
    viewerUserId: viewer,
    onOpenBeacon: () {},
    onOpenTimeline: () {},
    onClearEvent: (_) {},
  );
}

void main() {
  late ProductionReceiptTransport transport;
  setUpAll(() async {
    // Flutter widget tests default to Ahem. Use the app's font metrics when
    // checking whether a real headline would be clipped on a phone.
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
      inter.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await inter.load();
    transport = await ProductionReceiptTransport.start(
      serverFixture: 'test/support/baton_receipt_transport.dart',
    );
  });
  tearDownAll(() => transport.close());

  for (final language in ['en', 'ru']) {
    testWidgets(
      'Requests and Activity show complete baton answer and outcome headlines in $language',
      (tester) async {
        if (language == 'ru') {
          await usePhoneSurface(tester);
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = kPhoneSurface;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
        }
        final locale = Locale(language);
        final actual = <String, List<String>>{};
        final expected = <String, Matcher>{};
        for (final scenario in _cases) {
          final rows = (await tester.runAsync(
            () => _read(transport, scenario),
          ))!;
          final expectedHeadline = language == 'ru' ? scenario.ru : scenario.en;
          final requestKey = 'Requests, ${scenario.label}';
          final activityKey = 'Activity, ${scenario.label}';
          final isJoinedAnswer =
              scenario.key == _answered && scenario.request == _joined;
          final declineHeadline = language == 'ru' ? _declinedRu : _declinedEn;
          final expectedLine = isJoinedAnswer
              ? allOf(
                  isNot(anyElement(contains(declineHeadline))),
                  contains(expectedHeadline),
                )
              : contains(expectedHeadline);
          expected[requestKey] = expectedLine;
          expected[activityKey] = expectedLine;
          actual[requestKey] = await _render(
            tester,
            locale,
            _requestRow(rows.request),
            label: requestKey,
          );
          actual[activityKey] = await _render(
            tester,
            locale,
            _activityRow(rows.activity, scenario.viewer.id),
            label: activityKey,
          );
          if (isJoinedAnswer) {
            final receipt = rows.refetched;
            expect(
              receipt,
              isNotNull,
              reason: 'The joined receipt was refetched',
            );
            final refreshKey = 'Requests after refetch, ${scenario.label}';
            expected[refreshKey] = expectedLine;
            actual[refreshKey] = await _render(
              tester,
              locale,
              _requestRow(receipt!),
              label: refreshKey,
            );
          }
        }
        expect(actual, expected);
      },
    );
  }
}
