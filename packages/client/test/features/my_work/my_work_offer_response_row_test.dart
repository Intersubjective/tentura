import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

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

Future<void> _pumpMetadataRow(
  WidgetTester tester, {
  required MyWorkCardViewModel viewModel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: MyWorkCardMetadataRow(
                beacon: viewModel.beacon,
                viewModel: viewModel,
                currentUserId: 'viewer',
              ),
            ),
          ),
        ),
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

  testWidgets('renders awaiting author copy in YOU row', (tester) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.offered,
      ),
    );
    expect(find.byIcon(BeaconHudRowIcons.you), findsOneWidget);
    expect(find.text(l10n.beaconYouOfferSent), findsOneWidget);
    expect(find.text(l10n.myWorkOfferAwaitingAuthor), findsNothing);
  });

  testWidgets('accepted does not render standing accepted copy in YOU', (
    tester,
  ) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.acknowledged,
        authorResponseType: CoordinationResponseType.useful,
      ),
    );
    expect(find.text(l10n.myWorkOfferAccepted), findsNothing);
  });

  testWidgets('renders declined copy in YOU row', (tester) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.offered,
        authorResponseType: CoordinationResponseType.notSuitable,
      ),
    );
    expect(find.text(l10n.myWorkOfferDeclined), findsOneWidget);
  });

  testWidgets('renders softened copy in YOU row', (tester) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.softened,
      ),
    );
    expect(find.text(l10n.myWorkOfferSoftened), findsOneWidget);
  });

  testWidgets('renders participation ended copy in YOU row', (tester) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.released,
        authorResponseType: CoordinationResponseType.useful,
      ),
    );
    expect(find.text(l10n.myWorkOfferParticipationEnded), findsOneWidget);
  });

  testWidgets('renders exited copy in YOU row', (tester) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.open,
        stakeState: CommitmentStakeState.exited,
      ),
    );
    expect(find.text(l10n.myWorkOfferExited), findsOneWidget);
  });

  testWidgets('renders closed without response copy in YOU row', (tester) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.reviewOpen,
        stakeState: CommitmentStakeState.offered,
      ),
    );
    expect(find.text(l10n.myWorkOfferClosedWithoutResponse), findsOneWidget);
  });

  testWidgets('finished help-offered terminal shows YOU only', (tester) async {
    await _pumpMetadataRow(
      tester,
      viewModel: _helpOfferedVm(
        status: BeaconStatus.closed,
        stakeState: CommitmentStakeState.offered,
        authorResponseType: CoordinationResponseType.notSuitable,
        kind: MyWorkCardKind.helpOfferedFinished,
      ),
    );
    expect(find.byIcon(BeaconHudRowIcons.now), findsNothing);
    expect(find.byIcon(BeaconHudRowIcons.lastEvent), findsNothing);
    expect(find.byIcon(BeaconHudRowIcons.you), findsOneWidget);
    expect(find.text(l10n.myWorkOfferDeclined), findsOneWidget);
  });
}
