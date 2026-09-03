import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/closed_request_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Beacon _beacon({required BeaconStatus status}) => Beacon(
      id: 'B1',
      title: 't',
      status: status,
      author: const Profile(id: 'U1', displayName: 'a'),
      createdAt: DateTime.utc(2026, 6, 20),
      updatedAt: DateTime.utc(2026, 6, 20),
    );

Future<void> _pumpBanner(
  WidgetTester tester, {
  required Beacon beacon,
  required double width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 640)),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: ClosedRequestBanner(beacon: beacon),
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
  final open = _beacon(status: BeaconStatus.open);
  final closed = _beacon(status: BeaconStatus.closed);

  testWidgets('closed banner shown only for closed status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Column(
              children: [
                ClosedRequestBanner(beacon: open),
                ClosedRequestBanner(beacon: closed),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This request is closed'), findsOneWidget);
    expect(
      find.text(
        'It no longer produces responses, notifications, or trust evidence.',
      ),
      findsOneWidget,
    );
    expect(find.text('View my reviews'), findsOneWidget);
  });

  testWidgets('compact width places CTA below title', (tester) async {
    await _pumpBanner(tester, beacon: closed, width: 360);

    final title = tester.getRect(find.text('This request is closed'));
    final cta = tester.getRect(find.text('View my reviews'));
    expect(cta.top, greaterThanOrEqualTo(title.bottom));
  });

  testWidgets('wide width places CTA beside title', (tester) async {
    await _pumpBanner(tester, beacon: closed, width: 800);

    final title = tester.getRect(find.text('This request is closed'));
    final cta = tester.getRect(find.text('View my reviews'));
    expect(cta.left, greaterThanOrEqualTo(title.right));
    expect(cta.top, lessThan(title.bottom));
  });
}
