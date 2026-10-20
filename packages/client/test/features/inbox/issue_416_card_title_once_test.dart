// #416: a request card used to read "<title>\n<title>": the card tap target
// was labelled with the title and the visible title merged in again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_watchlist_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/a11y_spoken.dart';

class _FakeProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  testWidgets('a request card announces its title once', (tester) async {
    final handle = tester.ensureSemantics();
    const title = 'Fix the leaking kitchen sink';
    final at = DateTime.utc(2026, 6, 20, 12, 34);
    final beacon = Beacon(
      id: 'b-sink',
      title: title,
      author: const Profile(id: 'auth', displayName: 'Alex River'),
      createdAt: at,
      updatedAt: at,
    );

    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: _FakeProfileCubit(),
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 420)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 360,
                    child: InboxWatchlistRow(
                      item: InboxItem(
                        beaconId: beacon.id,
                        latestForwardAt: at,
                        beacon: beacon,
                      ),
                      onOpenBeacon: () {},
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(title), findsOneWidget);
    expect(spokenCount(title), 1, reason: spokenNodes().join(' | '));
    handle.dispose();
  });
}
