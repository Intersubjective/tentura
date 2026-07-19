import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/closed_request_banner.dart';

import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('closed banner shown only for closed status', (tester) async {
    final open = Beacon(
      id: 'B1',
      title: 't',
      status: BeaconStatus.open,
      author: const Profile(id: 'U1', displayName: 'a'),
      createdAt: DateTime.utc(2026, 6, 20),
      updatedAt: DateTime.utc(2026, 6, 20),
    );
    final closed = open.copyWith(status: BeaconStatus.closed);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              ClosedRequestBanner(beacon: open),
              ClosedRequestBanner(beacon: closed),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('closed'), findsOneWidget);
  });
}
