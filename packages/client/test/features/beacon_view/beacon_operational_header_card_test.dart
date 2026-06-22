import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_compact_metadata_strip.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  final t = DateTime.utc(2026, 6, 20);

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
          value: _MockProfileCubit(),
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

  testWidgets('NOW edit and detail taps are independent', (tester) async {
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

    var detailTaps = 0;
    var editTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<ProfileCubit>.value(
          value: _MockProfileCubit(),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconOperationalHeaderCard(
                state: state,
                onAuthorTap: () {},
                onShowNowDetail: () => detailTaps++,
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
    expect(detailTaps, 0);

    await tester.tap(find.byIcon(BeaconHudRowIcons.now));
    await tester.pumpAndSettle();
    expect(detailTaps, 1);
    expect(editTaps, 1);
  });
}
