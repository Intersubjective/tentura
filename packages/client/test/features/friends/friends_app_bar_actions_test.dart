import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/friends/domain/use_case/friends_case.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/friends/ui/screen/friends_screen.dart';
import 'package:tentura/features/friends/ui/widget/friends_app_bar_actions.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';

import '../../features/auth/auth_test_helpers.dart';
import '../../support/fake_block_case.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../contacts/contacts_case_test.dart';

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

class _FakeCapabilityRepository extends Fake
    implements CapabilityRepositoryPort {}

class _FakeLikeRemoteRepository extends Fake implements LikeRemoteRepository {}

class _FakeFriendsRemoteRepository extends Fake
    implements FriendsRemoteRepository {}

class _FakePresenceRepository extends Fake implements PresenceRepository {}

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

class _SignedInAuthLocal extends EmptyAuthLocal {
  @override
  Stream<String> currentAccountChanges() => Stream.value('account-1');
}

/// One pending people invite and one pending invite to a request.
class _PendingInvitesRepository extends _FakeInvitationRepository {
  static final _at = DateTime.utc(2026, 10, 20, 12);

  static final pending = [
    InvitationEntity(
      id: 'I0000000000a',
      createdAt: _at,
      updatedAt: _at,
      addresseeName: 'Ann',
    ),
    InvitationEntity(
      id: 'I0000000000b',
      createdAt: _at.add(const Duration(minutes: 1)),
      updatedAt: _at.add(const Duration(minutes: 1)),
      addresseeName: 'Bob',
      beaconId: 'B000000000001',
      beaconTitle: 'Move on Saturday',
    ),
  ];

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: pendingOffset == 0 ? pending : <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: pending.length,
  );
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
      'shows Graph, Invite, Scan and More at 320px without overflow',
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
        // #715: one label for creating an invite across People.
        expect(find.byTooltip('Invite someone you trust'), findsOneWidget);
        expect(find.byTooltip('More'), findsOneWidget);
        expect(find.byTooltip('Scan invite code'), findsOneWidget);
        expect(find.text('Blocked people'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('More menu lists Blocked people; scanning is in the bar', (
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

      expect(find.text('Scan invite code'), findsNothing);
      expect(find.text('Blocked people'), findsOneWidget);
    });

    testWidgets('trust info button opens trust info sheet', (tester) async {
      final l10n = lookupL10n(const Locale('en'));

      await _pumpFriendsAppBarActions(
        tester,
        onGraph: () {},
        onCreateInvitation: () {},
        onScanInvitationQr: () {},
        onBlockedPeople: () {},
      );

      expect(
        find.byKey(TestIds.key(TestIds.friendsTrustInfo)),
        findsOneWidget,
      );
      expect(find.byTooltip(l10n.trustInfoTitle), findsOneWidget);

      await tester.tap(find.byKey(TestIds.key(TestIds.friendsTrustInfo)));
      await tester.pumpAndSettle();

      expect(find.text(l10n.trustInfoTitle), findsOneWidget);
      expect(find.text(l10n.trustInfoBody), findsOneWidget);
      expect(find.byType(ContactBadgeLegend), findsOneWidget);
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

      await tester.tap(find.byTooltip('Scan invite code'));
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
    late ContactsCase contactsCase;
    late TestRealtimeSyncPort realtimePort;
    var registeredFriendsCubit = false;
    var registeredAuthCase = false;
    var registeredFriendsCase = false;
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
      // FriendsScreen feeds InvitationCubit from
      // FriendsCase.invitationServerChanges (B074).
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      final realtimeCase = realtime.case_;
      contactsCase = ContactsCase(
        FakeContactsRepository(),
        authCase,
        ContactNameStore(),
        realtimeCase,
        env: const Env(),
        logger: Logger('test'),
      );
      if (!getIt.isRegistered<FriendsCase>()) {
        getIt.registerSingleton<FriendsCase>(
          FriendsCase(
            _FakeCapabilityRepository(),
            _FakeInvitationRepository(),
            _FakeLikeRemoteRepository(),
            _FakeFriendsRemoteRepository(),
            _FakePresenceRepository(),
            contactsCase,
            authCase,
            realtimeCase,
            FakeBlockCase(),
            env: const Env(),
            logger: Logger('test'),
          ),
        );
        registeredFriendsCase = true;
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
      if (registeredFriendsCase && getIt.isRegistered<FriendsCase>()) {
        await getIt.unregister<FriendsCase>();
      }
      await contactsCase.dispose();
      await realtimePort.dispose();
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

    for (final entry in {
      'en': 'Your invites — links you created',
      'ru': 'Ваши приглашения — ссылки, которые вы создали',
    }.entries) {
      testWidgets('Invitations tab explains the section (${entry.key})', (
        tester,
      ) async {
        final profileCubit = _MockProfileCubit(
          const Profile(id: 'account-1', displayName: 'Me'),
        );
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            locale: Locale(entry.key),
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

        await tester.fling(
          find.byType(TabBarView),
          const Offset(-400, 0),
          1000,
        );
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget);
      });
    }
  });

  // #605 (from #452): re-opening a pending invite to a request from the
  // Invitations tab titled the share dialog «Invitation code», as for a plain
  // people invite.
  group('FriendsScreen re-opened invite', () {
    late FakeUiEffectPort effects;
    late ScreenCubit screenCubit;
    late ContactsCase contactsCase;
    late TestRealtimeSyncPort realtimePort;

    setUp(() {
      effects = FakeUiEffectPort();
      screenCubit = ScreenCubit.local(effects);
      final authCase = buildTestAuthCase(
        _SignedInAuthLocal(),
        EmptyAuthRemote(),
      );
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      contactsCase = ContactsCase(
        FakeContactsRepository(),
        authCase,
        ContactNameStore(),
        realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );
      GetIt.I
        ..registerSingleton<FriendsCubit>(_MockFriendsCubit())
        ..registerSingleton<AuthCase>(authCase)
        ..registerSingleton<InvitationRepository>(_PendingInvitesRepository())
        ..registerSingleton<FriendsCase>(
          FriendsCase(
            _FakeCapabilityRepository(),
            _FakeInvitationRepository(),
            _FakeLikeRemoteRepository(),
            _FakeFriendsRemoteRepository(),
            _FakePresenceRepository(),
            contactsCase,
            authCase,
            realtime.case_,
            FakeBlockCase(),
            env: const Env(),
            logger: Logger('test'),
          ),
        )
        ..registerSingleton<UiEffectPort>(effects);
    });

    tearDown(() async {
      await screenCubit.close();
      await GetIt.I.reset();
      await contactsCase.dispose();
      await realtimePort.dispose();
    });

    Future<void> openInvite(
      WidgetTester tester, {
      required String name,
      Locale locale = const Locale('en'),
    }) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ScreenCubit>.value(value: screenCubit),
              BlocProvider<ProfileCubit>.value(
                value: _MockProfileCubit(
                  const Profile(id: 'account-1', displayName: 'Me'),
                ),
              ),
            ],
            child: const FriendsScreen(initialTab: kHomeTabInvitations),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Precondition: both pending invites are listed.
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(ShareCodeDialog), findsOneWidget);
    }

    Finder dialogText(String text) => find.descendant(
      of: find.byType(ShareCodeDialog),
      matching: find.text(text),
    );

    for (final (locale, header, plainHeader) in [
      (const Locale('en'), 'Request invite', 'Invitation code'),
      (const Locale('ru'), 'Приглашение к запросу', 'Код приглашения'),
    ]) {
      testWidgets(
        'a request invite re-opens with the request header '
        '(${locale.languageCode})',
        (tester) async {
          await openInvite(tester, name: 'Bob', locale: locale);

          expect(dialogText(header), findsOneWidget);
          expect(dialogText(plainHeader), findsNothing);
          expect(
            find.descendant(
              of: find.byType(ShareCodeDialog),
              matching: find.textContaining('I0000000000b'),
            ),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('a people invite still re-opens as Invitation code', (
      tester,
    ) async {
      await openInvite(tester, name: 'Ann');

      expect(dialogText('Invitation code'), findsOneWidget);
      expect(dialogText('Request invite'), findsNothing);
    });
  });
}
