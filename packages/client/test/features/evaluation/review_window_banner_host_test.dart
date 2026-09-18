import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_author_act_block.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/features/evaluation/ui/widget/review_window_banner_host.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _Router extends Mock implements StackRouter {
  final pushed = <PageRouteInfo<dynamic>>[];
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();
  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo<dynamic> route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushed.add(route);
    return null;
  }
}

ReviewWindowInfo _window(
  ReviewPackageState package, {
  bool allRequiredSent = false,
}) => ReviewWindowInfo(
  beaconId: 'b1',
  hasWindow: package != ReviewPackageState.paused,
  closesAt: '2099-01-01T00:00:00.000Z',
  windowComplete:
      package == ReviewPackageState.closed ||
      package == ReviewPackageState.closedUnsent,
  userReviewStatus: switch (package) {
    ReviewPackageState.notEnrolled => -1,
    ReviewPackageState.sent => 2,
    _ => 1,
  },
  totalCount: package == ReviewPackageState.empty ? 0 : 4,
  requiredTotal: 3,
  requiredReviewed: package == ReviewPackageState.inProgress ? 1 : 3,
  // Legacy/optional counts must not determine required progress.
  optionalTotal: 1,
  sentAt:
      [
        ReviewPackageState.sent,
        ReviewPackageState.changedNotSent,
        ReviewPackageState.closed,
      ].contains(package)
      ? DateTime.utc(2026, 9, 18)
      : null,
  allRequiredSent: allRequiredSent,
  canCloseNow: allRequiredSent,
);

void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required ReviewWindowInfo? window,
    bool isAuthor = false,
    bool includeHud = false,
    BeaconStatus status = BeaconStatus.reviewOpen,
    String locale = 'en',
    _Router? router,
  }) async {
    final spec = deriveBeaconHudAuthorActSpec(
      l10n: lookupL10n(Locale(locale)),
      state: BeaconViewState(
        beacon: Beacon(
          id: 'b1',
          title: 'T',
          author: const Profile(id: 'author'),
          createdAt: DateTime.utc(2026, 9, 18),
          updatedAt: DateTime.utc(2026, 9, 18),
          status: status,
        ),
        myProfile: Profile(id: isAuthor ? 'author' : 'helper'),
        beaconContextLoaded: true,
        reviewWindowInfo: window,
      ),
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewWindowBannerHost(reviewWindowInfo: window, isAuthor: isAuthor),
        if (includeHud && spec != null)
          BeaconHudAuthorActBlock(spec: spec, onPressed: () {}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: Locale(locale),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: router == null
                ? body
                : StackRouterScope(
                    controller: router,
                    stateHash: 0,
                    child: body,
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (window != null) await tester.pumpAndSettle();
  }

  testWidgets('shows loading when snapshot is null', (tester) async {
    await pumpBanner(tester, window: null);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  for (final package in ReviewPackageState.values) {
    for (final isAuthor in [true, false]) {
      for (final allRequiredSent in [false, true]) {
        testWidgets('at most one primary review CTA per state: '
            '$package author=$isAuthor allRequiredSent=$allRequiredSent', (
          tester,
        ) async {
          final l10n = lookupL10n(const Locale('en'));
          await pumpBanner(
            tester,
            window: _window(package, allRequiredSent: allRequiredSent),
            isAuthor: isAuthor,
            includeHud: true,
            status: package == ReviewPackageState.paused
                ? BeaconStatus.open
                : BeaconStatus.reviewOpen,
          );
          final needsReview = [
            ReviewPackageState.inProgress,
            ReviewPackageState.readyToSend,
            ReviewPackageState.changedNotSent,
          ].contains(package);
          final count = needsReview && !(isAuthor && allRequiredSent) ? 1 : 0;
          expect(
            find.widgetWithText(
              FilledButton,
              l10n.beaconHudActReviewContributions,
            ),
            findsNWidgets(count),
          );
          // Catch duplicate/obsolete filled CTAs with any other label, too.
          expect(find.byType(FilledButton), findsNWidgets(count));
          expect(
            find.text(l10n.beaconHudActEffectReviewProgress(2, 3)),
            package == ReviewPackageState.inProgress && count == 1
                ? findsOneWidget
                : findsNothing,
          );
          final sent = package == ReviewPackageState.sent;
          expect(
            find.text(l10n.beaconHudReviewSent),
            sent ? findsOneWidget : findsNothing,
          );
          expect(
            find.widgetWithText(TextButton, l10n.beaconHudReviewEdit),
            sent ? findsOneWidget : findsNothing,
          );
          expect(
            find.text(l10n.beaconHudWaitingForAuthorClose),
            sent && !isAuthor ? findsOneWidget : findsNothing,
          );
          expect(
            find.text(l10n.beaconHudWaitingForRequiredReviews),
            sent && isAuthor && !allRequiredSent
                ? findsOneWidget
                : findsNothing,
          );
        });
      }
    }
  }

  testWidgets('no primary review CTA in sent', (tester) async {
    for (final isAuthor in [true, false]) {
      for (final allRequiredSent in [false, true]) {
        await pumpBanner(
          tester,
          window: _window(
            ReviewPackageState.sent,
            allRequiredSent: allRequiredSent,
          ),
          isAuthor: isAuthor,
          includeHud: true,
        );
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextButton), findsOneWidget);
      }
    }
  });

  testWidgets('the author keeps close-now in sent when allRequiredSent', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpBanner(
      tester,
      window: _window(ReviewPackageState.sent, allRequiredSent: true),
      isAuthor: true,
      includeHud: true,
    );
    expect(
      find.widgetWithText(OutlinedButton, l10n.beaconReviewCloseNowAction),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, l10n.beaconHudReviewEdit),
      findsOneWidget,
    );
    expect(find.text(l10n.beaconHudWaitingForRequiredReviews), findsNothing);
  });

  testWidgets('the author waiting on others does not see author-waiting copy', (
    tester,
  ) async {
    for (final locale in ['en', 'ru']) {
      final l10n = lookupL10n(Locale(locale));
      await pumpBanner(
        tester,
        window: _window(ReviewPackageState.sent),
        isAuthor: true,
        includeHud: true,
        locale: locale,
      );
      expect(
        find.text(l10n.beaconHudWaitingForRequiredReviews),
        findsOneWidget,
      );
      expect(find.text(l10n.beaconHudWaitingForAuthorClose), findsNothing);
      expect(find.text(l10n.beaconHudWaitingForReviews), findsNothing);
    }
  });

  testWidgets('Edit opens the sent package checklist for either role', (
    tester,
  ) async {
    for (final isAuthor in [true, false]) {
      final router = _Router();
      final l10n = lookupL10n(const Locale('en'));
      await pumpBanner(
        tester,
        window: _window(ReviewPackageState.sent),
        isAuthor: isAuthor,
        router: router,
      );
      await tester.tap(
        find.widgetWithText(TextButton, l10n.beaconHudReviewEdit),
      );
      await tester.pump();
      expect(router.pushed, hasLength(1));
      expect(router.pushed.single, isA<ReviewContributionsRoute>());
      expect(
        (router.pushed.single.args! as ReviewContributionsRouteArgs).id,
        'b1',
      );
    }
  });

  testWidgets('formats closesAt as localized date, not raw ISO string', (
    tester,
  ) async {
    await pumpBanner(tester, window: _window(ReviewPackageState.inProgress));
    expect(find.textContaining('2099-01-01T00:00:00.000Z'), findsNothing);
    final expected = DateFormat.yMMMd(
      'en',
    ).format(DateTime.parse('2099-01-01T00:00:00.000Z').toLocal());
    expect(find.textContaining(expected), findsOneWidget);
  });
}
