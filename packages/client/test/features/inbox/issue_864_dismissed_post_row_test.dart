import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_watchlist_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

class _FakeProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  testWidgets('dismissed Post row at 375×667 in RU reads as a Post', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final at = DateTime.utc(2026, 6, 20, 12, 34);
    const excerpt = 'Кто в субботу на велопрогулку?';
    final l10n = await L10n.delegate.load(const Locale('ru'));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
          BlocProvider(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: kPhoneSurface),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: InboxWatchlistRow(
                  item: InboxItem(
                    beaconId: 'Bdismissedpost1',
                    latestForwardAt: at,
                    status: InboxItemStatus.rejected,
                    roomHints: const InboxRoomCardHints(
                      isRoomMember: false,
                      roomUnreadCount: 0,
                      postRootExcerpt: excerpt,
                    ),
                    beacon: Beacon(
                      id: 'Bdismissedpost1',
                      kind: BeaconKind.post,
                      author: const Profile(
                        id: 'ualice',
                        displayName: 'Alice GQ2',
                      ),
                      createdAt: at,
                      updatedAt: at,
                    ),
                  ),
                  onOpenBeacon: () {},
                  onMoveToInbox: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.postRowSharedBy('Alice GQ2')),
      findsOneWidget,
    );
    expect(find.text(excerpt), findsOneWidget);
    expect(find.text(l10n.beaconPhaseLookingForHelpers), findsNothing);
    expect(find.text(l10n.beaconPhaseNoOffersYet), findsNothing);
    expect(find.text(l10n.openBeacon), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.constellationOpenPost), findsOneWidget);
    expect(find.text(l10n.forwardsGraphMenuTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
