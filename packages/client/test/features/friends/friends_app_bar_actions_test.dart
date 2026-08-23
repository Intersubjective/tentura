import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/friends/ui/screen/friends_screen.dart';
import 'package:tentura/features/friends/ui/widget/friends_app_bar_actions.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../features/auth/auth_test_helpers.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _MockFriendsCubit extends Mock implements FriendsCubit {
  @override
  FriendsState get state => const FriendsState(friends: {});

  @override
  Stream<FriendsState> get stream => Stream<FriendsState>.value(state);
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pumpFriendsAppBarActions(
  WidgetTester tester, {
  required VoidCallback onGraph,
  required VoidCallback onCreateInvitation,
  required VoidCallback onScanInvitationQr,
  required VoidCallback onBlockedPeople,
  Size size = const Size(320, 640),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        appBar: AppBar(
          actions: [
            FriendsAppBarActions(
              onGraph: onGraph,
              onCreateInvitation: onCreateInvitation,
              onScanInvitationQr: onScanInvitationQr,
              onBlockedPeople: onBlockedPeople,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('FriendsAppBarActions', () {
    testWidgets(
      'shows Graph, Create invitation, and More at 320px without overflow',
      (
        tester,
      ) async {
        await _pumpFriendsAppBarActions(
          tester,
          onGraph: () {},
          onCreateInvitation: () {},
          onScanInvitationQr: () {},
          onBlockedPeople: () {},
        );

        expect(find.byKey(TestIds.key(TestIds.friendsGraph)), findsOneWidget);
        expect(
          find.byKey(TestIds.key(TestIds.friendsCreateInvitation)),
          findsOneWidget,
        );
        expect(find.byKey(TestIds.key(TestIds.friendsMore)), findsOneWidget);
        expect(find.byTooltip('Graph'), findsOneWidget);
        expect(find.byTooltip('Create invitation'), findsOneWidget);
        expect(find.byTooltip('More'), findsOneWidget);
        expect(find.byTooltip('Scan invite code'), findsNothing);
        expect(find.text('Blocked people'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('More menu lists Scan invite code then Blocked people', (
      tester,
    ) async {
      await _pumpFriendsAppBarActions(
        tester,
        onGraph: () {},
        onCreateInvitation: () {},
        onScanInvitationQr: () {},
        onBlockedPeople: () {},
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.friendsMore)));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Scan invite code'), findsNothing);
      expect(find.text('Scan invite code'), findsOneWidget);
      expect(find.text('Blocked people'), findsOneWidget);

      final scanFinder = find.text('Scan invite code');
      final blockedFinder = find.text('Blocked people');
      final scanY = tester.getTopLeft(scanFinder).dy;
      final blockedY = tester.getTopLeft(blockedFinder).dy;
      expect(scanY, lessThan(blockedY));
    });

    testWidgets('each action invokes exactly its callback', (tester) async {
      var graphTaps = 0;
      var createTaps = 0;
      var scanTaps = 0;
      var blockedTaps = 0;

      await _pumpFriendsAppBarActions(
        tester,
        onGraph: () => graphTaps += 1,
        onCreateInvitation: () => createTaps += 1,
        onScanInvitationQr: () => scanTaps += 1,
        onBlockedPeople: () => blockedTaps += 1,
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.friendsGraph)));
      await tester.pump();
      expect(graphTaps, 1);

      await tester.tap(
        find.byKey(TestIds.key(TestIds.friendsCreateInvitation)),
      );
      await tester.pump();
      expect(createTaps, 1);

      await tester.tap(find.byKey(TestIds.key(TestIds.friendsMore)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan invite code'));
      await tester.pump();
      expect(scanTaps, 1);
      expect(blockedTaps, 0);

      await tester.tap(find.byKey(TestIds.key(TestIds.friendsMore)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blocked people'));
      await tester.pump();
      expect(blockedTaps, 1);
      expect(graphTaps, 1);
      expect(createTaps, 1);
      expect(scanTaps, 1);
    });
  });

  group('FriendsScreen graph navigation', () {
    late FakeUiEffectPort effects;
    late ScreenCubit screenCubit;
    late _MockFriendsCubit friendsCubit;
    late AuthCase authCase;
    var registeredFriendsCubit = false;
    var registeredAuthCase = false;
    var registeredInvitationRepository = false;
    var registeredUiEffectPort = false;

    setUp(() {
      effects = FakeUiEffectPort();
      screenCubit = ScreenCubit.local(effects);
      friendsCubit = _MockFriendsCubit();
      authCase = buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote());

      final getIt = GetIt.I;
      if (!getIt.isRegistered<FriendsCubit>()) {
        getIt.registerSingleton<FriendsCubit>(friendsCubit);
        registeredFriendsCubit = true;
      }
      if (!getIt.isRegistered<AuthCase>()) {
        getIt.registerSingleton<AuthCase>(authCase);
        registeredAuthCase = true;
      }
      if (!getIt.isRegistered<InvitationRepository>()) {
        getIt.registerSingleton<InvitationRepository>(
          _FakeInvitationRepository(),
        );
        registeredInvitationRepository = true;
      }
      if (!getIt.isRegistered<UiEffectPort>()) {
        getIt.registerSingleton<UiEffectPort>(effects);
        registeredUiEffectPort = true;
      }
    });

    tearDown(() async {
      await screenCubit.close();
      final getIt = GetIt.I;
      if (registeredFriendsCubit && getIt.isRegistered<FriendsCubit>()) {
        await getIt.unregister<FriendsCubit>();
      }
      if (registeredAuthCase && getIt.isRegistered<AuthCase>()) {
        await getIt.unregister<AuthCase>();
      }
      if (registeredInvitationRepository &&
          getIt.isRegistered<InvitationRepository>()) {
        await getIt.unregister<InvitationRepository>();
      }
      if (registeredUiEffectPort && getIt.isRegistered<UiEffectPort>()) {
        await getIt.unregister<UiEffectPort>();
      }
    });

    testWidgets('Graph uses ProfileCubit account id and emits NavigatePush', (
      tester,
    ) async {
      const accountId = 'account-graph-42';
      final profileCubit = _MockProfileCubit(
        const Profile(id: accountId, displayName: 'Me'),
      );

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ScreenCubit>.value(value: screenCubit),
              BlocProvider<ProfileCubit>.value(value: profileCubit),
            ],
            child: const FriendsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestIds.key(TestIds.friendsGraph)));
      await tester.pump();

      expect(
        effects.emitted.whereType<NavigatePush>().map((e) => e.path).toList(),
        ['$kPathGraph/$accountId'],
      );
    });
  });
}
