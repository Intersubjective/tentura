import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #516 residual (option A, Vadim 2026-10-22): when a helper withdraws, the
// author's Request card says who left and why. The server's helper-withdrawal
// receipt is `helpWithdrawn` (7.46.0) with `withdrawReason` (the reason key)
// and `leftDiscussion` in its payload and the helper's note as `excerpt`; a
// coordination promise's `promiseWithdrawn` still reads «Items updated».
//
// Pinned copy: the room line's own string, `beaconRoomParticipantLeft`, with
// `withdrawReasonLabel` for the key, then the note
// (`whoDidWhatReceiptDisplayCopy`).

const _note = 'Sorry, Saturday morning fell through';
const _requestTitle = 'Move a sofa';

const _author = Profile(id: 'a1', displayName: 'Tab QA');
const _helper = Profile(id: 'h1', displayName: 'Nina Mover');

final _beacon = Beacon(
  id: 'b1',
  title: _requestTitle,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 22),
  author: _author,
  viewerCanForward: true,
);

AttentionReceipt _withdrawn({
  String? withdrawReason = 'timing',
  String excerpt = _note,
  String? coordinationItemId,
}) => AttentionReceipt(
  id: 'e1',
  category: 'coordination',
  kind: 'commitmentEvent',
  priority: 'normal',
  title: 'Nina Mover',
  body: excerpt.isEmpty ? 'Nina Mover withdrew their help' : excerpt,
  actionUrl: '/#/',
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  collapsedCount: 1,
  presentationKey: coordinationItemId == null
      ? 'help_withdrawn'
      : 'promise_withdrawn',
  presentationPayloadJson: jsonEncode({
    'eventType': coordinationItemId == null
        ? 'helpWithdrawn'
        : 'promiseWithdrawn',
    if (coordinationItemId == null) 'leftDiscussion': true,
    'personal': false,
    'actorUserId': 'h1',
    'beaconId': 'b1',
    'targetEntityId': 'h1',
    'coordinationItemId': ?coordinationItemId,
    'beaconTitle': _requestTitle,
    'withdrawReason': ?withdrawReason,
    'excerpt': excerpt,
  }),
  surface: AttentionSurface.myWork,
  beaconId: 'b1',
  actorUserId: 'h1',
);

RequestAttentionCard _card(AttentionReceipt event) => RequestAttentionCard(
  beacon: _beacon,
  facts: const RequestAttentionFacts(
    requestId: 'b1',
    unclearedOptionalEvents: 1,
  ),
  eventTotal: 1,
  eventsPreview: [event],
  actors: const {'a1': _author, 'h1': _helper},
  onOpenBeacon: () {},
  onOpenTimeline: () {},
  onClearEvent: (_) {},
  onClearAll: () {},
);

Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(1280, 800)),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 600, child: child),
        ),
      ),
    ),
  ),
);

Finder _onChangeLine(Finder matching) => find.descendant(
  of: find.byKey(RequestAttentionCard.changeLineKey),
  matching: matching,
);

void main() {
  group('#516 the author sees who withdrew and why', () {
    testWidgets('en: name, reason label and note on the change line', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_card(_withdrawn())));
      await tester.pumpAndSettle();

      expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
      expect(
        _onChangeLine(
          find.text(
            'Nina Mover left the request (Timing no longer works) · '
            '$_note',
          ),
        ),
        findsOneWidget,
      );
      expect(_onChangeLine(find.text('Items updated')), findsNothing);
    });

    testWidgets('ru: the same line in Russian', (tester) async {
      await tester.pumpWidget(
        _host(_card(_withdrawn()), locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();

      expect(
        _onChangeLine(
          find.text(
            'Nina Mover покинул(а) запрос (Не сходится по времени) · '
            '$_note',
          ),
        ),
        findsOneWidget,
      );
      expect(_onChangeLine(find.text('Пункты обновлены')), findsNothing);
    });

    testWidgets('no note: name and reason only', (tester) async {
      await tester.pumpWidget(
        _host(_card(_withdrawn(withdrawReason: 'cannot_do_it', excerpt: ''))),
      );
      await tester.pumpAndSettle();

      expect(
        _onChangeLine(
          find.text('Nina Mover left the request (Cannot do it anymore)'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('guard: a withdrawn promise still reads Items updated', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _card(
            _withdrawn(
              withdrawReason: null,
              excerpt: 'Cannot bring the van',
              coordinationItemId: 'item1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_onChangeLine(find.text('Items updated')), findsOneWidget);
      expect(
        _onChangeLine(find.textContaining('left the request')),
        findsNothing,
      );
    });
  });
}
