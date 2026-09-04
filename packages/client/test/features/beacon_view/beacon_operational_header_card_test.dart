import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakePlatformRepository implements PlatformRepositoryPort {
  Uri? launchedUri;

  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {
    launchedUri = uri;
  }

  @override
  Future<void> launchUrl(String uri) async {
    launchedUri = Uri.parse(uri);
  }

  @override
  Future<void> launchUserLink(Uri uri) async {}
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

ReviewWindowInfo _reviewWindow({
  bool hasWindow = true,
  bool windowComplete = false,
  int? userReviewStatus = 0,
  int totalCount = 2,
  bool? canCloseNow,
}) =>
    ReviewWindowInfo(
      beaconId: 'b1',
      hasWindow: hasWindow,
      closesAt: '2099-01-01T00:00:00.000Z',
      windowComplete: windowComplete,
      userReviewStatus: userReviewStatus,
      totalCount: totalCount,
      canCloseNow: canCloseNow,
    );

Future<void> _pumpHeaderCard(
  WidgetTester tester, {
  required BeaconViewState state,
  void Function(BeaconHudAuthorAction action)? onAuthorHudAction,
  VoidCallback? onOfferHelp,
  VoidCallback? onEditHelpOffer,
  VoidCallback? onOpenPinnedFacts,
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
              onAuthorHudAction: onAuthorHudAction,
              onOfferHelp: onOfferHelp,
              onEditHelpOffer: onEditHelpOffer,
              onOpenPinnedFacts: onOpenPinnedFacts,
              onForward: onForward,
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

  testWidgets('HUD omits people strip; NOW is first metadata row', (
    tester,
  ) async {
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

    await _pumpHeaderCard(tester, state: state);

    expect(find.byIcon(BeaconHudRowIcons.people), findsNothing);
    expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
    expect(find.text('NOW'), findsNothing);
  });

  testWidgets('HUD Details affordance opens sheet with schedule and location', (
    tester,
  ) async {
    final beacon = Beacon(
      id: 'b-hud-sched-loc',
      title: 'Beacon HUD',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
      startAt: DateTime.utc(2099, 6, 20, 12),
      endAt: DateTime.utc(2099, 6, 25, 12),
      coordinates: const Coordinates(lat: 52.358, long: 4.881),
      addressLabel: 'Museumplein 6, Amsterdam',
    );
    final state = BeaconViewState(
      beacon: beacon,
      myProfile: const Profile(id: 'viewer', displayName: 'Viewer'),
      beaconContextLoaded: true,
    );

    await _pumpHeaderCard(tester, state: state);

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconDetailsSection), findsOneWidget);
    expect(find.byIcon(BeaconHudRowIcons.schedule), findsNothing);
    expect(find.text('Museumplein 6, Amsterdam'), findsNothing);

    await tester.tap(find.text(l10n.beaconDetailsSection));
    await tester.pumpAndSettle();

    expect(find.byIcon(BeaconHudRowIcons.schedule), findsOneWidget);
    expect(find.text('Museumplein 6, Amsterdam'), findsOneWidget);
  });

  testWidgets('HUD Details sheet location opens Maps URI', (
    tester,
  ) async {
    await GetIt.I.reset();
    final platform = _FakePlatformRepository();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);

    final beacon = Beacon(
      id: 'b-hud-location',
      title: 'Beacon HUD',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
      coordinates: const Coordinates(lat: 52.358, long: 4.881),
      addressLabel: 'Museumplein 6, Amsterdam',
    );
    final state = BeaconViewState(
      beacon: beacon,
      myProfile: const Profile(id: 'viewer', displayName: 'Viewer'),
      beaconContextLoaded: true,
    );

    await _pumpHeaderCard(tester, state: state);

    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.beaconDetailsSection));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Museumplein 6, Amsterdam'));
    await tester.pumpAndSettle();

    expect(find.text('Open in Maps'), findsOneWidget);

    await tester.tap(find.text('Open in Maps'));
    await tester.pumpAndSettle();

    expect(
      platform.launchedUri.toString(),
      'geo:52.358,4.881?q=52.358,4.881(Museumplein%206%2C%20Amsterdam)',
    );

    await GetIt.I.reset();
  });

  testWidgets('HUD access row shows Details and Facts with +N', (tester) async {
    var factsOpens = 0;
    final beacon = Beacon(
      id: 'b-hud-facts',
      title: 'Beacon HUD',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
      startAt: DateTime.utc(2099, 6, 20, 12),
    );
    final state = BeaconViewState(
      beacon: beacon,
      myProfile: const Profile(id: 'viewer', displayName: 'Viewer'),
      beaconContextLoaded: true,
      pinnedFactsSeenAt: DateTime.utc(2025),
      factCards: [
        BeaconFactCard(
          id: 'f1',
          beaconId: beacon.id,
          factText: 'Pinned',
          visibility: BeaconFactCardVisibilityBits.public,
          pinnedBy: 'other',
          createdAt: DateTime.utc(2026, 6, 21),
          status: BeaconFactCardStatusBits.active,
        ),
      ],
    );

    await _pumpHeaderCard(
      tester,
      state: state,
      onOpenPinnedFacts: () => factsOpens++,
    );

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconDetailsSection), findsOneWidget);
    expect(find.text(l10n.beaconFactsRowLabel), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.text(l10n.beaconYouNewCount(1)), findsOneWidget);

    await tester.tap(find.byKey(TestIds.key(TestIds.beaconFactsOpen)));
    await tester.pumpAndSettle();
    expect(factsOpens, 1);
  });

  testWidgets('HUD access row hides when neither Details nor Facts apply', (
    tester,
  ) async {
    final beacon = Beacon(
      id: 'b-hud-empty-row',
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

    await _pumpHeaderCard(tester, state: state);

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconDetailsSection), findsNothing);
    expect(find.text(l10n.beaconFactsRowLabel), findsNothing);
  });

  testWidgets('HUD Facts row shows for author with zero facts when openable', (
    tester,
  ) async {
    final state = BeaconViewState(
      beacon: _openAuthorBeacon(),
      myProfile: authorProfile,
      beaconContextLoaded: true,
    );
    var opens = 0;
    await _pumpHeaderCard(
      tester,
      state: state,
      onOpenPinnedFacts: () => opens++,
    );

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconFactsRowLabel), findsOneWidget);
    await tester.tap(find.byKey(TestIds.key(TestIds.beaconFactsOpen)));
    await tester.pumpAndSettle();
    expect(opens, 1);
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
      expect(
        find.text('Opens People; accept adds helper to the discussion'),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message ==
                  'Opens People; accept adds helper to the discussion',
        ),
        findsOneWidget,
      );
      expect(find.text('Update status'), findsNothing);
      expect(find.text('Forward'), findsNothing);
    });

    testWidgets('author ACT effect line wraps at compact width', (tester) async {
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

      await tester.binding.setSurfaceSize(const Size(375, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpHeaderCard(
        tester,
        state: state,
        onAuthorHudAction: (_) {},
      );

      expect(
        find.text('Opens People; accept adds helper to the discussion'),
        findsNothing,
      );
    });

    testWidgets('idle open author has no HUD ACT when onForward is absent', (
      tester,
    ) async {
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

      expect(find.text('Forward'), findsNothing);
      expect(find.text('Update status'), findsNothing);
    });

    testWidgets('idle open author shows Forward as the sole filled CTA', (
      tester,
    ) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(),
        myProfile: authorProfile,
        beaconContextLoaded: true,
      );

      var forwardTaps = 0;
      await _pumpHeaderCard(
        tester,
        state: state,
        onAuthorHudAction: (_) {},
        onForward: () => forwardTaps++,
      );

      final forwardBtn = find.widgetWithText(FilledButton, 'Forward');
      expect(forwardBtn, findsOneWidget);

      await tester.tap(forwardBtn);
      expect(forwardTaps, 1);
    });

    testWidgets(
      'Forward shows as a secondary CTA alongside the primary author action',
      (tester) async {
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
          onForward: () {},
        );

        expect(find.text('Review offers'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Forward'), findsOneWidget);
      },
    );

    testWidgets('Forward is hidden when the beacon does not allow forward', (
      tester,
    ) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(status: BeaconStatus.closed),
        myProfile: authorProfile,
        beaconContextLoaded: true,
      );

      await _pumpHeaderCard(
        tester,
        state: state,
        onAuthorHudAction: (_) {},
        onForward: () {},
      );

      expect(find.text('Forward'), findsNothing);
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

  group('helper HUD actions', () {
    testWidgets(
      'enoughHelp non-offered helper shows backup offer primary without Forward',
      (tester) async {
        const viewer = Profile(id: 'uViewer', displayName: 'Viewer');
        final state = BeaconViewState(
          beacon: _openAuthorBeacon(status: BeaconStatus.enoughHelp),
          myProfile: viewer,
          beaconContextLoaded: true,
        );

        var offerHelpTaps = 0;

        await _pumpHeaderCard(
          tester,
          state: state,
          onOfferHelp: () => offerHelpTaps++,
        );

        final backupPrimary = find.widgetWithText(
          FilledButton,
          'Offer as backup',
        );
        expect(backupPrimary, findsOneWidget);
        expect(tester.widget<FilledButton>(backupPrimary).onPressed, isNotNull);

        expect(find.text('Forward'), findsNothing);
        expect(find.byType(TenturaTextAction), findsNothing);

        await tester.tap(backupPrimary);
        await tester.pumpAndSettle();
        expect(offerHelpTaps, 1);
      },
    );

    testWidgets(
      'enoughHelp helper shows Forward alongside the backup offer primary '
      'when onForward is provided',
      (tester) async {
        const viewer = Profile(id: 'uViewer', displayName: 'Viewer');
        final state = BeaconViewState(
          beacon: _openAuthorBeacon(status: BeaconStatus.enoughHelp),
          myProfile: viewer,
          beaconContextLoaded: true,
        );

        await _pumpHeaderCard(
          tester,
          state: state,
          onOfferHelp: () {},
          onForward: () {},
        );

        expect(
          find.widgetWithText(FilledButton, 'Offer as backup'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Forward'), findsOneWidget);
      },
    );
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

  group('reviewOpen received-reviews CTA', () {
    Future<void> pumpReviewOpenHeader(
      WidgetTester tester, {
      required ReviewWindowInfo? reviewWindowInfo,
      required bool isAuthor,
    }) async {
      final myProfile = isAuthor
          ? authorProfile
          : const Profile(id: 'uViewer', displayName: 'Viewer');
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(status: BeaconStatus.reviewOpen),
        myProfile: myProfile,
        beaconContextLoaded: true,
        reviewWindowInfo: reviewWindowInfo,
      );

      await _pumpHeaderCard(tester, state: state);
    }

    testWidgets('renders while review window info is loading', (tester) async {
      final state = BeaconViewState(
        beacon: _openAuthorBeacon(status: BeaconStatus.reviewOpen),
        myProfile: const Profile(id: 'uViewer', displayName: 'Viewer'),
        beaconContextLoaded: true,
        reviewWindowInfo: null,
      );

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
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('See the reviews you receive'), findsOneWidget);
    });

    testWidgets('renders for non-author with outstanding review work', (
      tester,
    ) async {
      await pumpReviewOpenHeader(
        tester,
        reviewWindowInfo: _reviewWindow(),
        isAuthor: false,
      );

      expect(find.text('Review'), findsOneWidget);
      expect(find.text('See the reviews you receive'), findsOneWidget);
    });

    testWidgets('renders for author waiting on reviews', (tester) async {
      await pumpReviewOpenHeader(
        tester,
        reviewWindowInfo: _reviewWindow(
          userReviewStatus: 2,
          canCloseNow: false,
        ),
        isAuthor: true,
      );

      expect(find.text('Waiting for reviews'), findsOneWidget);
      expect(find.text('See the reviews you receive'), findsOneWidget);
    });

    testWidgets('renders when ReviewWindowBannerHost shrinks', (tester) async {
      await pumpReviewOpenHeader(
        tester,
        reviewWindowInfo: _reviewWindow(windowComplete: true),
        isAuthor: false,
      );

      expect(find.text('Review'), findsNothing);
      expect(find.text('Waiting for reviews'), findsNothing);
      expect(find.text('See the reviews you receive'), findsOneWidget);
    });
  });
}
