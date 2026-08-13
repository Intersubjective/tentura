import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/sheet/availability_sheet.dart';
import 'package:tentura/features/profile/ui/widget/profile_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 8, 14, 12);
  DateTime clock() => fixedNow;
  final todayUtc = availabilityTodayUtc(clock);
  final l10n = lookupL10n(const Locale('en'));

  const compactSize = Size(360, 220);
  const expandedSize = Size(1024, 220);

  final cases = <_GoldenCase>[
    _GoldenCase(
      id: 'open',
      profile: const Profile(id: 'U-me', displayName: 'Ada Lovelace'),
    ),
    _GoldenCase(
      id: 'limited',
      profile: Profile(
        id: 'U-me',
        displayName: 'Ada Lovelace',
        availability: const Availability(isLimited: true),
      ),
    ),
    _GoldenCase(
      id: 'paused',
      profile: Profile(
        id: 'U-me',
        displayName: 'Ada Lovelace',
        availability: Availability(resumeOn: DateTime.utc(2026, 8, 20)),
      ),
    ),
    _GoldenCase(
      id: 'limited_paused',
      profile: Profile(
        id: 'U-me',
        displayName: 'Ada Lovelace',
        availability: Availability(
          isLimited: true,
          resumeOn: DateTime.utc(2026, 8, 20),
        ),
      ),
    ),
  ];

  Future<void> pumpGolden(
    WidgetTester tester, {
    required _GoldenCase testCase,
    required Size logicalSize,
    required double textScaler,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: logicalSize,
            textScaler: TextScaler.linear(textScaler),
          ),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: Builder(
                  builder: (context) {
                    final tt = context.tt;
                    return RepaintBoundary(
                      key: const Key('golden'),
                      child: SizedBox(
                        width: logicalSize.width,
                        child: Padding(
                          padding: tt.cardPadding,
                          child: OwnProfileAvailabilityControl(
                            profile: testCase.profile,
                            todayUtc: todayUtc,
                            onChange: () {},
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('profile availability goldens', () {
    for (final testCase in cases) {
      testWidgets('${testCase.id} compact', (tester) async {
        await pumpGolden(
          tester,
          testCase: testCase,
          logicalSize: compactSize,
          textScaler: 1,
        );

        await expectLater(
          find.byKey(const Key('golden')),
          matchesGoldenFile(
            'goldens/profile_availability_${testCase.id}_compact.png',
          ),
        );
      });

      testWidgets('${testCase.id} expanded', (tester) async {
        await pumpGolden(
          tester,
          testCase: testCase,
          logicalSize: expandedSize,
          textScaler: 1,
        );

        await expectLater(
          find.byKey(const Key('golden')),
          matchesGoldenFile(
            'goldens/profile_availability_${testCase.id}_expanded.png',
          ),
        );
      });

      testWidgets('${testCase.id} compact text scale 1.3', (tester) async {
        await pumpGolden(
          tester,
          testCase: testCase,
          logicalSize: compactSize,
          textScaler: 1.3,
        );

        await expectLater(
          find.byKey(const Key('golden')),
          matchesGoldenFile(
            'goldens/profile_availability_${testCase.id}_compact_s1_3.png',
          ),
        );
      });
    }

    testWidgets('sanity: primary lines match localization helpers', (tester) async {
      for (final testCase in cases) {
        await pumpGolden(
          tester,
          testCase: testCase,
          logicalSize: compactSize,
          textScaler: 1,
        );
        final primary = ownAvailabilityPrimaryLine(
          l10n,
          testCase.profile.availability,
          todayUtc,
        );
        expect(find.text(primary), findsOneWidget);
        final secondary = ownAvailabilitySecondaryLine(
          l10n,
          testCase.profile.availability,
          todayUtc,
        );
        if (secondary != null) {
          expect(find.text(secondary), findsOneWidget);
        }
        expect(find.text(l10n.availabilityChangeAction), findsOneWidget);
      }
    });
  });
}

final class _GoldenCase {
  const _GoldenCase({
    required this.id,
    required this.profile,
  });

  final String id;
  final Profile profile;
}
