@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #532 — a pinned fact's «Anna · 2m ago» was read off the clock once, when
/// the line was built. It follows the shared ticking clock.
final _created = DateTime.utc(2026, 10, 14, 12);

void main() {
  late DateTime clock;

  setUp(() {
    clock = _created.add(const Duration(minutes: 2));
    RelativeTimestampTicker.debugClock = () => clock;
  });
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  testWidgets('a fact provenance age keeps counting while open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: FactProvenanceLine(
              fact: BeaconFactCard(
                id: 'f1',
                beaconId: 'b1',
                factText: 'Gate code is 4821',
                visibility: BeaconFactCardVisibilityBits.public,
                pinnedBy: 'Uanna',
                pinnedByTitle: 'Anna',
                createdAt: _created,
                status: BeaconFactCardStatusBits.active,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Anna · 2m ago'), findsOneWidget);

    clock = clock.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Anna · 4m ago'), findsOneWidget);
  });
}
