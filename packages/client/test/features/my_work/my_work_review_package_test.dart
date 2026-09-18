import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_review_affordance.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_cta.dart';

import '../evaluation/evaluation_case_test.dart' show FakeEvaluationRepository;
import 'my_work_test_support.dart';

const _author = 'Ua';
const _helper = 'Uh';

MyWorkCardViewModel _card(
  String id, {
  MyWorkCardRole role = MyWorkCardRole.helpOffered,
  ReviewPackageState? package,
  bool allRequiredSent = false,
}) => MyWorkCardViewModel(
  beaconId: id,
  role: role,
  kind: role == MyWorkCardRole.authored
      ? MyWorkCardKind.authoredActive
      : MyWorkCardKind.helpOfferedActive,
  beacon: Beacon.empty.copyWith(
    id: id,
    author: const Profile(id: _author),
    status: BeaconStatus.reviewOpen,
  ),
  reviewPackageState: package,
  reviewAllRequiredSent: allRequiredSent,
);

ReviewWindowInfo _window(
  String id, {
  int? userReviewStatus = 1,
  DateTime? sentAt,
  int requiredTotal = 2,
  int requiredReviewed = 0,
  bool hasWindow = true,
  bool canCloseNow = false,
}) => ReviewWindowInfo(
  beaconId: id,
  hasWindow: hasWindow,
  userReviewStatus: userReviewStatus,
  sentAt: sentAt,
  requiredTotal: requiredTotal,
  requiredReviewed: requiredReviewed,
  totalCount: 2,
  canCloseNow: canCloseNow,
);

Future<L10n> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(child: Scaffold(body: child)),
    ),
  );
  return lookupL10n(const Locale('en'));
}

void main() {
  group('loadReviewWindows', () {
    test('fetches windows for help-offered reviewOpen cards too', () async {
      final eval = FakeEvaluationRepository()
        ..reviewWindowStatusesResult = [
          _window('B1', userReviewStatus: 2, sentAt: DateTime.utc(2026, 9)),
          _window('B2'),
        ];
      final case_ = buildTestMyWorkCase(evaluationRepo: eval);

      final out = await case_.loadReviewWindows([
        _card('B1', role: MyWorkCardRole.authored),
        _card('B2'),
        _card('B3'),
      ], userId: _author);

      expect(eval.lastReviewWindowStatusesIds, ['B1', 'B2', 'B3']);
      final byId = {for (final c in out) c.beaconId: c};
      expect(byId['B1']!.reviewPackageState, ReviewPackageState.sent);
      expect(byId['B1']!.showReviewCta, isFalse);
      expect(byId['B2']!.reviewPackageState, ReviewPackageState.inProgress);
      expect(byId['B2']!.showReviewCta, isTrue);
      // Missing row: the window is gone for this viewer.
      expect(byId['B3']!.reviewPackageState, ReviewPackageState.notEnrolled);
      expect(byId['B3']!.showReviewCta, isFalse);
    });
  });

  testWidgets('a sent package shows no primary review CTA on the card', (
    tester,
  ) async {
    for (final (role, viewer, allSent) in [
      (MyWorkCardRole.authored, _author, false),
      (MyWorkCardRole.helpOffered, _helper, true),
    ]) {
      final vm = _card(
        'B1',
        role: role,
        package: ReviewPackageState.sent,
        allRequiredSent: allSent,
      );
      expect(
        myWorkEffectivePrimaryAction(vm: vm, viewerUserId: viewer),
        isNot(BeaconPhasePrimaryAction.reviewContributions),
      );
      expect(
        myWorkObligationBlockVisible(vm: vm, obligations: const []),
        isFalse,
      );
      final l10n = await _pump(
        tester,
        MyWorkReviewAffordance(
          vm: vm,
          isAuthor: viewer == _author,
          onOpenReview: () {},
        ),
      );
      expect(find.byType(TenturaCommandButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text(l10n.beaconHudReviewSent), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, l10n.beaconHudReviewEdit),
        findsOneWidget,
      );
      expect(
        find.text(
          viewer == _author
              ? l10n.beaconHudWaitingForRequiredReviews
              : l10n.beaconHudWaitingForAuthorClose,
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('an edited package shows the send-changes affordance', (
    tester,
  ) async {
    final vm = _card('B1', package: ReviewPackageState.changedNotSent);
    final l10n = await _pump(
      tester,
      MyWorkReviewAffordance(vm: vm, isAuthor: false, onOpenReview: () {}),
    );
    expect(
      find.widgetWithText(TenturaCommandButton, l10n.evaluationSubmitChanges),
      findsOneWidget,
    );

    final ready = _card('B2', package: ReviewPackageState.readyToSend);
    await _pump(
      tester,
      MyWorkReviewAffordance(vm: ready, isAuthor: false, onOpenReview: () {}),
    );
    expect(
      find.widgetWithText(
        TenturaCommandButton,
        l10n.beaconHudActReviewContributions,
      ),
      findsOneWidget,
    );
  });

  test('an authored card with canCloseNow still shows close now', () async {
    final eval = FakeEvaluationRepository()
      ..reviewWindowStatusesResult = [
        _window(
          'B1',
          userReviewStatus: 2,
          sentAt: DateTime.utc(2026, 9),
          canCloseNow: true,
        ),
      ];
    final case_ = buildTestMyWorkCase(evaluationRepo: eval);

    final out = await case_.loadReviewWindows([
      _card('B1', role: MyWorkCardRole.authored),
    ], userId: _author);

    expect(out.single.showCloseNowCta, isTrue);
    expect(out.single.reviewPackageState, ReviewPackageState.sent);
    expect(out.single.showReviewCta, isFalse);
  });

  testWidgets('a card whose window is gone shows no review affordance', (
    tester,
  ) async {
    for (final package in [
      null,
      ReviewPackageState.notEnrolled,
      ReviewPackageState.paused,
      ReviewPackageState.closed,
      ReviewPackageState.closedUnsent,
      ReviewPackageState.empty,
    ]) {
      final vm = _card('B1', package: package);
      expect(myWorkReviewAffordanceKind(package), MyWorkReviewAffordanceKind.none);
      expect(
        myWorkEffectivePrimaryAction(vm: vm, viewerUserId: _author),
        isNot(BeaconPhasePrimaryAction.reviewContributions),
      );
      await _pump(
        tester,
        MyWorkReviewAffordance(vm: vm, isAuthor: false, onOpenReview: () {}),
      );
      expect(find.byType(TenturaCommandButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    }
  });
}
