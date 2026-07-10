import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/ui/widget/review_window_banner_host.dart';
import 'package:tentura/ui/l10n/l10n.dart';

ReviewWindowInfo _window({
  bool hasWindow = true,
  bool windowComplete = false,
  int? userReviewStatus = 0,
  int totalCount = 2,
  int reviewedCount = 0,
  bool? canCloseNow,
}) =>
    ReviewWindowInfo(
      beaconId: 'b1',
      hasWindow: hasWindow,
      closesAt: '2099-01-01T00:00:00.000Z',
      windowComplete: windowComplete,
      userReviewStatus: userReviewStatus,
      reviewedCount: reviewedCount,
      totalCount: totalCount,
      canCloseNow: canCloseNow,
    );

void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required ReviewWindowInfo? window,
    bool isAuthor = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: ReviewWindowBannerHost(
              reviewWindowInfo: window,
              isAuthor: isAuthor,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (window != null) {
      await tester.pumpAndSettle();
    }
  }

  group('ReviewWindowInfo.viewerHasOutstandingReviewWork', () {
    test('true for enrolled viewer with open window and targets', () {
      expect(_window().viewerHasOutstandingReviewWork, isTrue);
    });

    test('false when finalized or not enrolled', () {
      expect(
        _window(userReviewStatus: 2).viewerHasOutstandingReviewWork,
        isFalse,
      );
      expect(
        _window(userReviewStatus: -1).viewerHasOutstandingReviewWork,
        isFalse,
      );
      expect(_window(totalCount: 0).viewerHasOutstandingReviewWork, isFalse);
    });
  });

  group('ReviewWindowBannerHost', () {
    testWidgets('shows loading when snapshot is null', (tester) async {
      await pumpBanner(tester, window: null);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Review for enrolled viewer with outstanding work', (
      tester,
    ) async {
      await pumpBanner(tester, window: _window());

      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('author waiting shows waiting copy', (tester) async {
      await pumpBanner(
        tester,
        window: _window(userReviewStatus: 2, canCloseNow: false),
        isAuthor: true,
      );

      expect(find.text('Waiting for reviews'), findsOneWidget);
      expect(find.text('Extend review'), findsNothing);
    });

    testWidgets('author with personal review work hides waiting banner', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        window: _window(userReviewStatus: 0),
        isAuthor: true,
      );

      expect(find.text('Waiting for reviews'), findsNothing);
      expect(find.text('Review'), findsNothing);
    });
  });
}
