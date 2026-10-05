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
        'It no longer takes new offers or sends notifications.',
      ),
      findsOneWidget,
    );
  });
}
