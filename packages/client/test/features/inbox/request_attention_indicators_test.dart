import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_indicators.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  double textScaler = 1,
  Size size = const Size(360, 640),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScaler),
    ),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: size.width, child: child),
        ),
      ),
    ),
  ),
);

RequestAttentionFacts _facts({int optional = 0, int obligations = 0}) =>
    RequestAttentionFacts(
      requestId: 'R1',
      unclearedOptionalEvents: optional,
      liveObligations: obligations,
    );

final _dot = find.byKey(RequestAttentionIndicators.dotKey);
final _count = find.byKey(RequestAttentionIndicators.countKey);

void main() {
  group('D09 — a Request card shows dot and count independently', () {
    testWidgets('an uncleared optional event alone shows the dot only', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(RequestAttentionIndicators(facts: _facts(optional: 1))),
      );
      expect(_dot, findsOneWidget);
      expect(_count, findsNothing);
    });

    testWidgets('live obligations alone show the count only', (tester) async {
      await tester.pumpWidget(
        _host(RequestAttentionIndicators(facts: _facts(obligations: 2))),
      );
      expect(_dot, findsNothing);
      expect(_count, findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('both are present at once — neither hides the other', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RequestAttentionIndicators(facts: _facts(optional: 3, obligations: 4)),
        ),
      );
      expect(_dot, findsOneWidget, reason: 'the count must not hide the dot');
      expect(_count, findsOneWidget, reason: 'the dot must not hide the dot');
      expect(
        find.text('4'),
        findsOneWidget,
        reason: 'the number counts obligations, not optional events',
      );
    });

    testWidgets('nothing renders when there is nothing to act on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const RequestAttentionIndicators(facts: RequestAttentionFacts(requestId: 'R1'))),
      );
      expect(_dot, findsNothing);
      expect(_count, findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('an uncleared outcome alone is a dot', (tester) async {
      await tester.pumpWidget(
        _host(
          const RequestAttentionIndicators(
            facts: RequestAttentionFacts(
              requestId: 'R1',
              unclearedOutcomes: 1,
            ),
          ),
        ),
      );
      expect(_dot, findsOneWidget);
      expect(_count, findsNothing);
    });

    testWidgets('the card reads the same rule the indicators do', (
      tester,
    ) async {
      final facts = _facts(optional: 1, obligations: 5);
      await tester.pumpWidget(_host(RequestAttentionIndicators(facts: facts)));
      expect(_dot.evaluate().isNotEmpty, requestHasDot(facts));
      expect(
        _count.evaluate().isNotEmpty,
        requestCount(facts) > 0,
        reason: 'the card must not invent a second rule',
      );
      expect(find.text('${requestCount(facts)}'), findsOneWidget);
    });

    testWidgets('both survive 1.3x text at 360 dp', (tester) async {
      await tester.pumpWidget(
        _host(
          RequestAttentionIndicators(facts: _facts(optional: 1, obligations: 7)),
          textScaler: 1.3,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_dot, findsOneWidget);
      expect(_count, findsOneWidget);
    });

    testWidgets('the dot and the count carry distinct semantics', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('en'));
      await tester.pumpWidget(
        _host(RequestAttentionIndicators(facts: _facts(optional: 1, obligations: 3))),
      );
      expect(
        find.bySemanticsLabel(l10n.activityNavBadgeNewActivity),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.myWorkNavBadgeObligations(3)),
        findsOneWidget,
      );
    });
  });
}
