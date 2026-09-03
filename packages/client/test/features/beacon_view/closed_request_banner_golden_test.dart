import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/closed_request_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> _pumpBanner(
  WidgetTester tester, {
  required Size logicalSize,
}) async {
  final beacon = Beacon(
    id: 'B1',
    title: 't',
    status: BeaconStatus.closed,
    author: const Profile(id: 'U1', displayName: 'a'),
    createdAt: DateTime.utc(2026, 6, 20),
    updatedAt: DateTime.utc(2026, 6, 20),
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: logicalSize),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: logicalSize.width,
                  child: ClosedRequestBanner(beacon: beacon),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ClosedRequestBanner golden compact 360', (tester) async {
    await _pumpBanner(tester, logicalSize: const Size(360, 200));
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/closed_request_banner_360.png'),
    );
  });

  testWidgets('ClosedRequestBanner golden wide 800', (tester) async {
    await _pumpBanner(tester, logicalSize: const Size(800, 200));
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/closed_request_banner_800.png'),
    );
  });
}
