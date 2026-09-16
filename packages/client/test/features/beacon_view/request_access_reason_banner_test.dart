import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _bannerText =
    'You can see this request because you take part in a related request.';

Beacon _beacon({
  required BeaconAccessLevel? accessLevel,
  int accessReasons = 0,
}) => Beacon(
  id: 'B1',
  title: 't',
  author: const Profile(id: 'U1', displayName: 'a'),
  createdAt: DateTime.utc(2026, 6, 20),
  updatedAt: DateTime.utc(2026, 6, 20),
  accessLevel: accessLevel,
  accessReasons: accessReasons,
);

Future<void> _pumpBanner(WidgetTester tester, Beacon beacon) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: RequestAccessReasonBanner(beacon: beacon),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shown for context-child observer', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 64),
    );
    expect(find.text(_bannerText), findsOneWidget);
  });

  testWidgets('shown for context-ancestor observer', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 128),
    );
    expect(find.text(_bannerText), findsOneWidget);
  });

  testWidgets('hidden for member even with a context bit', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.member, accessReasons: 64),
    );
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('hidden for author', (tester) async {
    await _pumpBanner(tester, _beacon(accessLevel: BeaconAccessLevel.author));
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('hidden without a server access level', (tester) async {
    await _pumpBanner(tester, _beacon(accessLevel: null, accessReasons: 64));
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('hidden for forwarded-only observer', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 8),
    );
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('applied takes priority over context', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 16 | 64),
    );
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('context takes priority over discovered', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 32 | 64),
    );
    expect(find.text(_bannerText), findsOneWidget);
  });
}
