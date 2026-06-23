import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
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
  BeaconCoordinationStatus coordinationStatus =
      BeaconCoordinationStatus.neutral,
  BeaconLifecycle lifecycle = BeaconLifecycle.open,
}) =>
    Beacon(
      id: 'b1',
      title: 'T',
      author: const Profile(id: 'uAuthor', displayName: 'Author'),
      createdAt: DateTime.utc(2026, 6, 20),
      updatedAt: DateTime.utc(2026, 6, 20),
      lifecycle: lifecycle,
      coordinationStatus: coordinationStatus,
    );

Future<void> _pumpHeaderCard(
  WidgetTester tester, {
  required BeaconViewState state,
  VoidCallback? onUpdateStatus,
  VoidCallback? onForward,
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
              onUpdateStatus: onUpdateStatus,
              onForward: onForward ?? () {},
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

  group('Update status CTA visibility', () {
    testWidgets('shown when author has unanswered help offers', (tester) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: authorProfile,
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
        onUpdateStatus: () {},
      );

      expect(find.text('Update status'), findsOneWidget);
    });

    testWidgets('Update status shown when coordination is blocked', (
      tester,
    ) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(
          coordinationStatus:
              BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
        ),
        myProfile: authorProfile,
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onUpdateStatus: () {},
      );

      expect(find.text('Resolve'), findsNothing);
      expect(find.text('Update status'), findsOneWidget);
      expect(find.text('Forward'), findsOneWidget);
    });

    testWidgets('hidden on closed beacon even when callback wired', (
      tester,
    ) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(lifecycle: BeaconLifecycle.closed),
        myProfile: authorProfile,
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onUpdateStatus: () {},
      );

      expect(find.text('Update status'), findsNothing);
    });

    testWidgets('shown for steward when callback wired', (tester) async {
      const stewardProfile = Profile(id: 'uSteward', displayName: 'Steward');
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: stewardProfile,
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
        onUpdateStatus: () {},
      );

      expect(find.text('Update status'), findsOneWidget);
    });
  });

  group('removed HUD CTAs', () {
    testWidgets('open author shows Forward and Update status without Close', (
      tester,
    ) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: authorProfile,
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onUpdateStatus: () {},
      );

      expect(find.text('Forward'), findsOneWidget);
      expect(find.text('Update status'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
    });

    testWidgets('steward shows Forward and Update status without Close', (
      tester,
    ) async {
      const stewardProfile = Profile(id: 'uSteward', displayName: 'Steward');
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: stewardProfile,
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
        onUpdateStatus: () {},
      );

      expect(find.text('Forward'), findsOneWidget);
      expect(find.text('Update status'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
    });

    testWidgets('closed author shows no Review Log or View chain CTAs', (
      tester,
    ) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(lifecycle: BeaconLifecycle.closed),
        myProfile: authorProfile,
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onUpdateStatus: () {},
      );

      expect(find.text('Review'), findsNothing);
      expect(find.text('Log'), findsNothing);
      expect(find.text('View chain'), findsNothing);
      expect(find.text('Forward'), findsNothing);
      expect(find.text('Update status'), findsNothing);
    });
  });
}
