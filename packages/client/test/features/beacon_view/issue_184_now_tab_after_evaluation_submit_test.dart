import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_you_responsibility_line.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

/// Post–Send and complete author snapshot on request `B678bc1ca1d1e` trail
/// (review window still open, package submitted, close-now not yet allowed — #162).
BeaconViewState _postSubmitAuthorNowState({
  String beaconId = 'B678bc1ca1d1e',
}) {
  const author = Profile(id: 'U6fca01549512', displayName: 'Author');
  final beacon = Beacon(
    id: beaconId,
    title: 'QA close/review loop',
    author: author,
    createdAt: DateTime.utc(2026, 9, 14),
    updatedAt: DateTime.utc(2026, 9, 14, 19, 2),
    status: BeaconStatus.reviewOpen,
    reviewClosesAt: DateTime.utc(2026, 9, 21),
  );
  return BeaconViewState(
    beacon: beacon,
    myProfile: author,
    beaconContextLoaded: true,
    reviewWindowInfo: const ReviewWindowInfo(
      beaconId: 'B678bc1ca1d1e',
      hasWindow: true,
      userReviewStatus: 2,
      totalCount: 2,
      reviewedCount: 2,
      canCloseNow: false,
    ),
    beaconRoomCue: BeaconRoomState(
      beaconId: beaconId,
      updatedAt: DateTime.utc(2026, 9, 14, 19, 2),
      currentLine: '',
      openBlockerTitle: '',
    ),
    youResponsibility: const CoordinationResponsibility(
      beaconId: 'B678bc1ca1d1e',
      blockerOpen: 1,
    ),
  );
}

Future<void> _pumpOperationalHeader(
  WidgetTester tester, {
  required BeaconViewState state,
  void Function(BeaconHudAuthorAction action)? onAuthorHudAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(state.myProfile),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconOperationalHeaderCard(
              state: state,
              onAuthorTap: () {},
              onAuthorHudAction: onAuthorHudAction,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('issue #184 — Now tab after evaluation submit', () {
    testWidgets(
      'operational header survives semantics flush (post-submit reviewOpen author)',
      (tester) async {
        final state = _postSubmitAuthorNowState();
        await _pumpOperationalHeader(
          tester,
          state: state,
          onAuthorHudAction: (_) {},
        );
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
        expect(find.byType(BeaconOperationalHeaderCard), findsOneWidget);
      },
    );

    testWidgets(
      'YOU row does not throw when blocker counts outlive open blocker cue',
      (tester) async {
        final state = _postSubmitAuthorNowState();
        final phaseResult = const BeaconCoordinationPhaseResult(
          phase: BeaconCoordinationPhase.blocked,
          suggestedAction: BeaconPhasePrimaryAction.resolveBlocker,
          rowHarmony: BeaconPhaseRowHarmony(
            preferBlockedYouSegment: true,
            showBlockedTitleInNowSubline: true,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('ru'),
            home: TenturaResponsiveScope(
              child: Scaffold(
                body: BeaconYouResponsibilityLine(
                  beacon: state.beacon,
                  responsibility: state.youResponsibility!,
                  isAuthorOrSteward: true,
                  authorUnreviewedHelpOfferCount: 0,
                  tableRowWidth: 360,
                  viewerUserId: state.myProfile.id,
                  openBlocker: null,
                  phaseResult: phaseResult,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
