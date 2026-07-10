import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_compact_metadata_strip.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Beacon _openAuthorBeacon({
  BeaconStatus status = BeaconStatus.open,
}) =>
    Beacon(
      id: 'b1',
      title: 'T',
      author: const Profile(id: 'uAuthor', displayName: 'Author'),
      createdAt: DateTime.utc(2026, 6, 20),
      updatedAt: DateTime.utc(2026, 6, 20),
      status: status,
    );

Future<void> _pumpHeaderCard(
  WidgetTester tester, {
  required BeaconViewState state,
  void Function(BeaconHudAuthorAction action)? onAuthorHudAction,
  VoidCallback? onForward,
  VoidCallback? onEditHelpOffer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(state.myProfile),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconOperationalHeaderCard(
              state: state,
              onAuthorTap: () {},
              onAuthorHudAction: onAuthorHudAction,
              onForward: onForward ?? () {},
              onEditHelpOffer: onEditHelpOffer,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final t = DateTime.utc(2026, 6, 20);
  const authorProfile = Profile(id: 'uAuthor', displayName: 'Author');

  testWidgets('HUD renders compact metadata strip before NOW row', (tester) async {
    final beacon = Beacon(
      id: 'b-hud',
      title: 'Beacon HUD',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
      startAt: DateTime.utc(2099, 6, 20, 12),
    );
    final state = BeaconViewState(
      beacon: beacon,
      myProfile: const Profile(id: 'viewer', displayName: 'Viewer'),
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'help',
          createdAt: t,
          updatedAt: t,
        ),
      ],
      beaconContextLoaded: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<ProfileCubit>.value(
          value: _MockProfileCubit(const Profile(id: 'viewer', displayName: 'Viewer')),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconOperationalHeaderCard(
                state: state,
                onAuthorTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BeaconCompactMetadataStrip), findsOneWidget);
    expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
    expect(find.text('NOW'), findsNothing);

    final stripY = tester.getTopLeft(find.byType(BeaconCompactMetadataStrip)).dy;
    final nowY = tester.getTopLeft(find.byIcon(BeaconHudRowIcons.now)).dy;
    expect(stripY, lessThan(nowY));
  });

  testWidgets('NOW edit works and row body is not tappable', (tester) async {
    final beacon = Beacon(
      id: 'b-hud-tap',
      title: 'Beacon HUD',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
    );
    final state = BeaconViewState(
      beacon: beacon,
      myProfile: const Profile(id: 'viewer', displayName: 'Viewer'),
      beaconContextLoaded: true,
    );

    var editTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<ProfileCubit>.value(
          value: _MockProfileCubit(const Profile(id: 'viewer', displayName: 'Viewer')),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconOperationalHeaderCard(
                state: state,
                onAuthorTap: () {},
                onEditNowLine: () => editTaps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(editTaps, 1);

    await tester.tap(find.byIcon(BeaconHudRowIcons.now));
    await tester.pumpAndSettle();
    expect(editTaps, 1);
  });

  group('author single ACT', () {
    testWidgets('shows Review offers when unanswered help offers exist', (
      tester,
    ) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: authorProfile,
        beaconContextLoaded: true,
        helpOffers: [
          TimelineHelpOffer(
            user: const Profile(id: 'h1', displayName: 'Helper'),
            message: 'help',
            createdAt: t,
            updatedAt: t,
          ),
        ],
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onAuthorHudAction: (_) {},
      );

      expect(find.text('Review offers'), findsOneWidget);
      expect(find.text('Update status'), findsNothing);
      expect(find.text('Forward'), findsNothing);
    });

    testWidgets('idle open author shows muted Forward', (tester) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: authorProfile,
        beaconContextLoaded: true,
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onAuthorHudAction: (_) {},
      );

      expect(find.text('Forward'), findsOneWidget);
      expect(find.text('Update status'), findsNothing);
    });

    testWidgets('steward shows no author HUD actions', (tester) async {
      const stewardProfile = Profile(id: 'uSteward', displayName: 'Steward');
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: stewardProfile,
        beaconContextLoaded: true,
        roomParticipants: [
          BeaconParticipant(
            id: 'p1',
            beaconId: 'b1',
            userId: 'uSteward',
            role: BeaconParticipantRoleBits.steward,
            status: BeaconParticipantStatusBits.committed,
            roomAccess: RoomAccessBits.admitted,
            createdAt: t,
            updatedAt: t,
          ),
        ],
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onAuthorHudAction: (_) {},
      );

      expect(find.text('Forward'), findsNothing);
      expect(find.text('Update status'), findsNothing);
    });
  });

  group('removed HUD CTAs', () {
    testWidgets('waiting help offerer shows Edit help offer CTA', (tester) async {
      const viewer = Profile(id: 'uViewer', displayName: 'Viewer');
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: viewer,
        isHelpOffered: true,
        beaconContextLoaded: true,
        helpOffers: [
          TimelineHelpOffer(
            user: viewer,
            message: 'I can help',
            createdAt: t,
            updatedAt: t,
          ),
        ],
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onEditHelpOffer: () {},
      );

      expect(find.text('Edit help offer'), findsOneWidget);
      expect(find.text('Offer help'), findsNothing);
    });

    testWidgets('rejected help offerer does not show Edit help offer CTA', (
      tester,
    ) async {
      const viewer = Profile(id: 'uViewer', displayName: 'Viewer');
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: viewer,
        isHelpOffered: true,
        beaconContextLoaded: true,
        helpOffers: [
          TimelineHelpOffer(
            user: viewer,
            message: 'I can help',
            createdAt: t,
            updatedAt: t,
            coordinationResponse: CoordinationResponseType.notSuitable,
          ),
        ],
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onEditHelpOffer: () {},
      );

      expect(find.text('Edit help offer'), findsNothing);
    });
  });
}
