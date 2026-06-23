import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/ui/widget/review_window_banner_host.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _ReviewWindowRepoFake extends Fake implements EvaluationRepository {
  ReviewWindowInfo? response;

  @override
  Future<ReviewWindowInfo> fetchReviewWindowStatus(String beaconId) async =>
      response!;
}

ReviewWindowInfo _window({
  bool hasWindow = true,
  bool windowComplete = false,
  int? userReviewStatus = 0,
  int totalCount = 2,
  int reviewedCount = 0,
}) =>
    ReviewWindowInfo(
      beaconId: 'b1',
      hasWindow: hasWindow,
      closesAt: '2099-01-01T00:00:00.000Z',
      windowComplete: windowComplete,
      userReviewStatus: userReviewStatus,
      reviewedCount: reviewedCount,
      totalCount: totalCount,
    );

void main() {
  late _ReviewWindowRepoFake repo;

  setUp(() {
    repo = _ReviewWindowRepoFake();
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<EvaluationRepository>()) {
      await GetIt.I.reset();
    }
  });

  Future<void> pumpBanner(
    WidgetTester tester, {
    required ReviewWindowInfo window,
    bool isAuthor = false,
  }) async {
    repo.response = window;
    GetIt.I.registerSingleton<EvaluationRepository>(repo);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: ReviewWindowBannerHost(
              beaconId: 'b1',
              isAuthor: isAuthor,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
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
    testWidgets('shows Review for enrolled viewer with outstanding work', (
      tester,
    ) async {
      await pumpBanner(tester, window: _window());

      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('hides Review when viewer finalized review', (tester) async {
      await pumpBanner(tester, window: _window(userReviewStatus: 2));

      expect(find.text('Review'), findsNothing);
    });

    testWidgets('hides Review when viewer has no evaluation targets', (
      tester,
    ) async {
      await pumpBanner(tester, window: _window(totalCount: 0));

      expect(find.text('Review'), findsNothing);
    });

    testWidgets('author management actions visible when isAuthor', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        window: _window(userReviewStatus: 2),
        isAuthor: true,
      );

      expect(find.text('Review'), findsNothing);
      expect(find.text('Extend review'), findsOneWidget);
      expect(find.text('Reopen'), findsOneWidget);
      expect(find.text('Close now'), findsOneWidget);
    });
  });
}
