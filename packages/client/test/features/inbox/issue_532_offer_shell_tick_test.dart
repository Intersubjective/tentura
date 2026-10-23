@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_bounded_shell.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #532 — the bounded offer card on the Requests desk read its age once, at
/// build time. It follows the shared ticking clock, with no data change.
final _created = DateTime.utc(2026, 10, 14, 12);

void main() {
  late DateTime clock;

  setUp(() {
    clock = _created.add(const Duration(seconds: 30));
    RelativeTimestampTicker.debugClock = () => clock;
  });
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  testWidgets('an offer card age keeps counting while open', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: ActivityOfferBoundedShell(
              leading: const SizedBox.square(dimension: 24),
              headline: 'Petr offers help',
              whyLine: 'Van to the lake',
              createdAt: _created,
              showUnseenDot: false,
              onBodyTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('now'), findsOneWidget);

    clock = clock.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('now'), findsNothing);
    expect(find.text('2m'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('2 minutes ago')), findsWidgets);
    semantics.dispose();
  });
}
