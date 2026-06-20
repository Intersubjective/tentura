import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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

  testWidgets('authored open neutral hides strip', (tester) async {
    final l10n = await loadL10n(tester);
    final vm = MyWorkCardViewModel(
      beaconId: 'n',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: 'n',
        lifecycle: BeaconLifecycle.open,
        coordinationStatus: BeaconCoordinationStatus.neutral,
        helpOfferCount: 2,
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm);
    expect(line.isEmpty, isTrue);
  });

  testWidgets('authored open needsMoreHelp shows slot1 only', (tester) async {
    final l10n = await loadL10n(tester);
    final vm = MyWorkCardViewModel(
      beaconId: 'm',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: 'm',
        lifecycle: BeaconLifecycle.open,
        coordinationStatus: BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm);
    expect(line.slot1, l10n.myWorkStatusNeedsMoreHelp);
    expect(line.slot2, isEmpty);
    expect(
      line.slot1CoordinationStatus,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
    );
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
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm, now: now);
    expect(line.slot1, l10n.myWorkStatusWrappingUp);
    expect(line.slot2, isNotEmpty);
  });

  testWidgets('committed active folds author response into slot1', (
    tester,
  ) async {
    final l10n = await loadL10n(tester);
    final vm = MyWorkCardViewModel(
      beaconId: 'c',
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedActive,
      beacon: Beacon.empty.copyWith(
        id: 'c',
        lifecycle: BeaconLifecycle.open,
        coordinationStatus: BeaconCoordinationStatus.enoughHelpOffered,
      ),
      authorResponseType: CoordinationResponseType.useful,
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm);
    expect(
      line.slot1,
      l10n.myWorkStatusHelpOfferWithResponse(
        l10n.myWorkStatusHelpOfferedPersonal.toLowerCase(),
        l10n.coordinationUseful.toLowerCase(),
      ),
    );
    expect(line.slot2, isEmpty);
    expect(line.slot1ResponseType, CoordinationResponseType.useful);
  });

  testWidgets('help offered reviewOpen shows wrapping up', (tester) async {
    final l10n = await loadL10n(tester);
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
      ),
      showReviewCta: true,
    );
    final line = myWorkStatusLine(
      l10n: l10n,
      vm: vm,
      now: DateTime.utc(2026, 6, 22),
    );
    expect(line.slot1, l10n.myWorkStatusWrappingUp);
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
    expect(line.slot1, l10n.myWorkStatusClosed);
    expect(line.slot2, isEmpty);
  });
}
