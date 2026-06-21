import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

void main() {
  Future<L10n> loadL10n(WidgetTester tester) async {
    L10n? l10nRef;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            l10nRef = L10n.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return l10nRef!;
  }

  MyWorkStatusLineData expectedFromPresenter(
    L10n l10n,
    MyWorkCardViewModel vm, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final input = beaconPhaseInputFromMyWorkCard(vm, now: clock);
    final result = deriveBeaconCoordinationPhase(input);
    final pres = formatBeaconPhaseStatus(l10n, result, now: clock);
    return MyWorkStatusLineData(
      slot1: pres.statusLine,
      slot2: '',
      timeSlotOverdue: false,
      tone: pres.tone,
    );
  }

  testWidgets('authored open neutral with offers shows offers awaiting author', (
    tester,
  ) async {
    final l10n = await loadL10n(tester);
    final now = DateTime.utc(2026, 6, 22, 12);
    final vm = MyWorkCardViewModel(
      beaconId: 'n',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: 'n',
        lifecycle: BeaconLifecycle.open,
        coordinationStatus: BeaconCoordinationStatus.neutral,
        helpOfferCount: 2,
        updatedAt: now,
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm, now: now);
    final expected = expectedFromPresenter(l10n, vm, now: now);
    expect(line.isEmpty, isFalse);
    expect(line.slot1, expected.slot1);
    expect(line.slot2, isEmpty);
    expect(line.tone, TenturaTone.info);
  });

  testWidgets('authored open needsMoreHelp shows phase status line', (
    tester,
  ) async {
    final l10n = await loadL10n(tester);
    final now = DateTime.utc(2026, 6, 22, 12);
    final vm = MyWorkCardViewModel(
      beaconId: 'm',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: 'm',
        lifecycle: BeaconLifecycle.open,
        coordinationStatus: BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm, now: now);
    final expected = expectedFromPresenter(l10n, vm, now: now);
    expect(line.slot1, expected.slot1);
    expect(line.slot1, contains(l10n.beaconPhaseNeedsMoreHelp));
    expect(line.slot2, isEmpty);
    expect(line.tone, TenturaTone.warn);
  });

  testWidgets('authored reviewOpen shows wrapping up and countdown', (
    tester,
  ) async {
    final l10n = await loadL10n(tester);
    final closesAt = DateTime.utc(2026, 6, 25, 12);
    final now = DateTime.utc(2026, 6, 22, 12);
    final vm = MyWorkCardViewModel(
      beaconId: 'a',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: 'a',
        lifecycle: BeaconLifecycle.reviewOpen,
        coordinationStatus: BeaconCoordinationStatus.enoughHelpOffered,
        reviewClosesAt: closesAt,
        reviewWindowStatus: 0,
        helpOfferCount: 3,
        updatedAt: now,
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm, now: now);
    final expected = expectedFromPresenter(l10n, vm, now: now);
    expect(line.slot1, expected.slot1);
    expect(line.slot1, contains(l10n.beaconPhaseWrappingUp));
    expect(line.slot2, isEmpty);
    expect(line.tone, TenturaTone.info);
  });

  testWidgets('help offered enough help shows shared phase status', (
    tester,
  ) async {
    final l10n = await loadL10n(tester);
    final now = DateTime.utc(2026, 6, 22, 12);
    final vm = MyWorkCardViewModel(
      beaconId: 'c',
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedActive,
      beacon: Beacon.empty.copyWith(
        id: 'c',
        lifecycle: BeaconLifecycle.open,
        coordinationStatus: BeaconCoordinationStatus.enoughHelpOffered,
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm, now: now);
    final expected = expectedFromPresenter(l10n, vm, now: now);
    expect(line.slot1, expected.slot1);
    expect(line.slot1, contains(l10n.beaconPhaseEnoughHelpInMotion));
    expect(line.slot2, isEmpty);
    expect(line.tone, TenturaTone.good);
  });

  testWidgets('help offered reviewOpen shows wrapping up', (tester) async {
    final l10n = await loadL10n(tester);
    final now = DateTime.utc(2026, 6, 22);
    final vm = MyWorkCardViewModel(
      beaconId: 'x',
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedActive,
      beacon: Beacon.empty.copyWith(
        id: 'x',
        lifecycle: BeaconLifecycle.reviewOpen,
        coordinationStatus: BeaconCoordinationStatus.enoughHelpOffered,
        reviewClosesAt: DateTime.utc(2026, 6, 25),
        reviewWindowStatus: 0,
        updatedAt: now,
      ),
      showReviewCta: true,
    );
    final line = myWorkStatusLine(
      l10n: l10n,
      vm: vm,
      now: now,
    );
    final expected = expectedFromPresenter(l10n, vm, now: now);
    expect(line.slot1, expected.slot1);
    expect(line.slot1, contains(l10n.beaconPhaseWrappingUp));
    expect(line.tone, TenturaTone.info);
  });

  testWidgets('authored finished shows closed', (tester) async {
    final l10n = await loadL10n(tester);
    final vm = MyWorkCardViewModel(
      beaconId: 'f',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredFinished,
      beacon: Beacon.empty.copyWith(
        id: 'f',
        lifecycle: BeaconLifecycle.closed,
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm);
    final expected = expectedFromPresenter(l10n, vm);
    expect(line.slot1, expected.slot1);
    expect(line.slot1, l10n.beaconPhaseClosed);
    expect(line.slot2, isEmpty);
    expect(line.tone, TenturaTone.neutral);
  });
}
