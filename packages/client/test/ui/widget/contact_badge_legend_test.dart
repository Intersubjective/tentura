import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';

void main() {
  Future<void> pumpLegend(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ContactBadgeLegend(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('isSeeingMe uses rScore not score', () {
    expect(const Profile(id: 'open', rScore: 1).isSeeingMe, isTrue);
    expect(const Profile(id: 'closed', score: 50).isSeeingMe, isFalse);
  });

  test('isMutuallyVisible requires both score directions', () {
    expect(
      const Profile(id: 'mutual', score: 1, rScore: 1).isMutuallyVisible,
      isTrue,
    );
    expect(
      const Profile(id: 'in-only', rScore: 1).isMutuallyVisible,
      isFalse,
    );
    expect(
      const Profile(id: 'out-only', score: 50).isMutuallyVisible,
      isFalse,
    );
    expect(const Profile(id: 'none').isMutuallyVisible, isFalse);
  });

  testWidgets('contact badge legend lists mutual and eye rows', (tester) async {
    await pumpLegend(tester);

    expect(find.text('People badges'), findsOneWidget);
    expect(
      find.textContaining('Mutual trust'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Open eye'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Closed eye'),
      findsOneWidget,
    );
    expect(find.byType(TenturaAvatar), findsNWidgets(3));
  });
}
