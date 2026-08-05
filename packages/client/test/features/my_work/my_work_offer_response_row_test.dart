import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_offer_response_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

MyWorkCardViewModel _helpOfferedVm({
  required BeaconStatus status,
  required CommitmentStakeState stakeState,
  CoordinationResponseType? authorResponseType,
  MyWorkCardKind kind = MyWorkCardKind.helpOfferedActive,
}) {
  final beacon = Beacon.empty.copyWith(
    id: 'b1',
    status: status,
  );
  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.helpOffered,
    kind: kind,
    beacon: beacon,
    authorResponseType: authorResponseType,
    stakeState: stakeState,
  );
}

Future<void> _pumpRow(
  WidgetTester tester, {
  required MyWorkCardViewModel viewModel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: MyWorkOfferResponseRow(viewModel: viewModel),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late L10n l10n;

  setUp(() {
    l10n = lookupL10n(const Locale('en'));
  });

  testWidgets('renders awaiting author copy', (tester) async {
    await _pumpRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.offered,
      ),
    );
    expect(find.text(l10n.myWorkOfferAwaitingAuthor), findsOneWidget);
  });

  testWidgets('renders accepted copy', (tester) async {
    await _pumpRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.acknowledged,
        authorResponseType: CoordinationResponseType.useful,
      ),
    );
    expect(find.text(l10n.myWorkOfferAccepted), findsOneWidget);
  });

  testWidgets('renders declined copy', (tester) async {
    await _pumpRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.offered,
        authorResponseType: CoordinationResponseType.notSuitable,
      ),
    );
    expect(find.text(l10n.myWorkOfferDeclined), findsOneWidget);
  });

  testWidgets('renders softened copy', (tester) async {
    await _pumpRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.softened,
      ),
    );
    expect(find.text(l10n.myWorkOfferSoftened), findsOneWidget);
  });

  testWidgets('renders participation ended copy', (tester) async {
    await _pumpRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.released,
        authorResponseType: CoordinationResponseType.useful,
      ),
    );
    expect(find.text(l10n.myWorkOfferParticipationEnded), findsOneWidget);
  });

  testWidgets('renders exited copy', (tester) async {
    await _pumpRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.exited,
      ),
    );
    expect(find.text(l10n.myWorkOfferExited), findsOneWidget);
  });

  testWidgets('renders closed without response copy', (tester) async {
    await _pumpRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.reviewOpen,
        stakeState: CommitmentStakeState.offered,
      ),
    );
    expect(find.text(l10n.myWorkOfferClosedWithoutResponse), findsOneWidget);
  });

  testWidgets('hides row for authored cards', (tester) async {
    final beacon = Beacon.empty.copyWith(
      id: 'a1',
      status: BeaconStatus.open,
    );
    await _pumpRow(
      tester,
      viewModel: MyWorkCardViewModel(
        beaconId: beacon.id,
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredActive,
        beacon: beacon,
      ),
    );
    expect(find.byType(MyWorkOfferResponseRow), findsOneWidget);
    expect(find.text(l10n.myWorkOfferAwaitingAuthor), findsNothing);
  });
}
