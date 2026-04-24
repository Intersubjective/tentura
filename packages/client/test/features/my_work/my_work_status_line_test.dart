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
  testWidgets('committed review-open status matches post-close grammar', (
    tester,
  ) async {
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
    final l10n = l10nRef!;

    final vm = MyWorkCardViewModel(
      beaconId: 'x',
      role: MyWorkCardRole.committed,
      kind: MyWorkCardKind.committedActive,
      beacon: Beacon.empty.copyWith(
        id: 'x',
        lifecycle: BeaconLifecycle.closedReviewOpen,
        coordinationStatus: BeaconCoordinationStatus.enoughHelpCommitted,
      ),
      showReadyForReviewChip: true,
      showReviewCta: true,
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm);
    expect(line.slot1, l10n.myWorkStatusReadyForReview);
    expect(line.slot2, l10n.myWorkStatusMirrorClosed);
    expect(line.slot3, l10n.myWorkStatusAcknowledgeContributions);
  });

  testWidgets('committed active folds author response into slot1', (
    tester,
  ) async {
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
    final l10n = l10nRef!;

    final vm = MyWorkCardViewModel(
      beaconId: 'c',
      role: MyWorkCardRole.committed,
      kind: MyWorkCardKind.committedActive,
      beacon: Beacon.empty.copyWith(
        id: 'c',
        lifecycle: BeaconLifecycle.open,
        coordinationStatus: BeaconCoordinationStatus.enoughHelpCommitted,
      ),
      authorResponseType: CoordinationResponseType.useful,
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm);
    expect(line.slot3, l10n.myWorkStatusMirrorEnoughHelp);
    expect(
      line.slot1,
      l10n.myWorkStatusCommitmentWithResponse(
        l10n.myWorkStatusCommittedPersonal.toLowerCase(),
        l10n.coordinationUseful.toLowerCase(),
      ),
    );
  });

  testWidgets('authored closedReviewOpen uses Closed · review open · participants',
      (tester) async {
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
    final l10n = l10nRef!;

    final vm = MyWorkCardViewModel(
      beaconId: 'a',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: 'a',
        lifecycle: BeaconLifecycle.closedReviewOpen,
        coordinationStatus: BeaconCoordinationStatus.enoughHelpCommitted,
        commitmentCount: 3,
      ),
    );
    final line = myWorkStatusLine(l10n: l10n, vm: vm);
    expect(line.slot1, l10n.myWorkStatusClosed);
    expect(line.slot2, l10n.myWorkStatusReviewOpen);
    expect(line.slot3, l10n.myWorkStatusNParticipants(3));
  });
}
