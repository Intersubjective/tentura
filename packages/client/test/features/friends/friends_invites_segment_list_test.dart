// #1153: Pending invites with only people rows must render list tiles (not
// only the section caption). Covers FriendsScreen's real invites segment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

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
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';
import '../../support/fake_block_case.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
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

class _ConfigurableInvitationRepository extends Fake
    implements InvitationRepository {
  _ConfigurableInvitationRepository({
    required this.pending,
    required this.accepted,
    required this.pendingCount,
  });

  final List<InvitationEntity> pending;
  final List<InvitationEntity> accepted;
  final int pendingCount;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: pendingOffset == 0 ? pending : <InvitationEntity>[],
    accepted: acceptedOffset == 0 ? accepted : <InvitationEntity>[],
    pendingCount: pendingCount,
  );
}

class _SignedInAuthLocal extends EmptyAuthLocal {
  @override
  Stream<String> currentAccountChanges() => Stream.value('account-1');
}

final _at = DateTime.utc(2026, 10, 20, 12);

InvitationEntity _peoplePending({
  required String id,
  required String addresseeName,
}) => InvitationEntity(
  id: id,
  createdAt: _at,
  updatedAt: _at,
  addresseeName: addresseeName,
);

InvitationEntity _requestPending({
  required String id,
  required String addresseeName,
  required String beaconTitle,
}) => InvitationEntity(
  id: id,
  createdAt: _at.add(const Duration(minutes: 1)),
  updatedAt: _at.add(const Duration(minutes: 1)),
  addresseeName: addresseeName,
  beaconId: 'B000000000001',
  beaconTitle: beaconTitle,
);

InvitationEntity _acceptedPeople({
  required String id,
  required String invitedName,
}) => InvitationEntity(
  id: id,
  createdAt: _at,
  updatedAt: _at,
  acceptedAt: _at.add(const Duration(hours: 1)),
  invitedId: 'U000000000001',
  invitedName: invitedName,
  inviteOrigin: 'new_account',
);

Future<void> _registerFriendsHarness(InvitationRepository invitations) async {
  final authCase = buildTestAuthCase(
    _SignedInAuthLocal(),
    EmptyAuthRemote(),
  );
  final realtime = buildTestRealtimeSync();
  final contactsCase = ContactsCase(
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
    ..registerSingleton<InvitationRepository>(invitations)
    ..registerSingleton<FriendsCase>(
      FriendsCase(
        _FakeCapabilityRepository(),
        invitations,
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
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort());
}

Future<void> _pumpInvitesSegment(
  WidgetTester tester, {
  required Locale locale,
  required ScreenCubit screenCubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
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
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _wireQueryRoot({
  required List<Map<String, dynamic>> pending,
  required List<Map<String, dynamic>> accepted,
  required int pendingCount,
}) => {
  '__typename': 'query_root',
  'pending': pending,
  'accepted': accepted,
  'pending_count': {
    '__typename': 'invitation_aggregate',
    'aggregate': {
      '__typename': 'invitation_aggregate_fields',
      'count': pendingCount,
    },
  },
};

Map<String, dynamic> _wirePendingRow({
  required String id,
  required String addresseeName,
}) => {
  '__typename': 'invitation',
  'id': id,
  'beacon_id': null,
  'invited_id': null,
  'addressee_name': addresseeName,
  'invite_origin': null,
  'accepted_at': null,
  'created_at': '2026-10-30T00:00:00+00:00',
  'updated_at': '2026-10-30T00:00:00+00:00',
  'invited': null,
  'beacon': null,
};

void main() {
  group('FriendsScreen invites segment (#1153)', () {
    late ScreenCubit screenCubit;

    setUp(() {
      screenCubit = ScreenCubit.local(FakeUiEffectPort());
    });

    tearDown(() async {
      await screenCubit.close();
      await GetIt.I.reset();
    });

    for (final locale in [const Locale('en'), const Locale('ru')]) {
      testWidgets(
        'Pending with only a people invite shows one row with edit and delete '
        '(${locale.languageCode}, 375×667)',
        (tester) async {
          await usePhoneSurface(tester);
          final l10n = lookupL10n(locale);
          const name = 'Clara';
          await _registerFriendsHarness(
            _ConfigurableInvitationRepository(
              pending: [_peoplePending(id: 'Ipeople001', addresseeName: name)],
              accepted: const [],
              pendingCount: 1,
            ),
          );

          await _pumpInvitesSegment(
            tester,
            locale: locale,
            screenCubit: screenCubit,
          );

          expect(find.text(name), findsOneWidget);
          expect(find.text(l10n.friendsInvitesPeopleSection), findsNothing);
          expect(
            find.byTooltip(l10n.invitationAddresseeEditTitle),
            findsOneWidget,
          );
          expect(find.byTooltip(l10n.buttonDelete), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final locale in [const Locale('en'), const Locale('ru')]) {
      testWidgets(
        'Pending with people and request invites shows both section headers '
        '(${locale.languageCode}, 375×667)',
        (tester) async {
          await usePhoneSurface(tester);
          final l10n = lookupL10n(locale);
          await _registerFriendsHarness(
            _ConfigurableInvitationRepository(
              pending: [
                _peoplePending(id: 'Ipeople001', addresseeName: 'Ann'),
                _requestPending(
                  id: 'Irequest01',
                  addresseeName: 'Bob',
                  beaconTitle: 'Move on Saturday',
                ),
              ],
              accepted: const [],
              pendingCount: 2,
            ),
          );

          await _pumpInvitesSegment(
            tester,
            locale: locale,
            screenCubit: screenCubit,
          );

          expect(find.text('Ann'), findsOneWidget);
          expect(find.text('Bob'), findsOneWidget);
          expect(find.text('Move on Saturday'), findsOneWidget);
          expect(find.text(l10n.friendsInvitesPeopleSection), findsOneWidget);
          expect(find.text(l10n.friendsInvitesBeaconSection), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final locale in [const Locale('en'), const Locale('ru')]) {
      testWidgets(
        'Pending with no invites shows the empty state '
        '(${locale.languageCode}, 375×667)',
        (tester) async {
          await usePhoneSurface(tester);
          final l10n = lookupL10n(locale);
          await _registerFriendsHarness(
            _ConfigurableInvitationRepository(
              pending: const [],
              accepted: const [],
              pendingCount: 0,
            ),
          );

          await _pumpInvitesSegment(
            tester,
            locale: locale,
            screenCubit: screenCubit,
          );

          expect(
            find.text(l10n.friendsInvitesPendingEmptyTitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n.friendsInvitesPendingEmptyBody),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final locale in [const Locale('en'), const Locale('ru')]) {
      testWidgets(
        'Accepted segment still lists accepted people invites '
        '(${locale.languageCode}, 375×667)',
        (tester) async {
          await usePhoneSurface(tester);
          final l10n = lookupL10n(locale);
          const joinedName = 'Theo';
          await _registerFriendsHarness(
            _ConfigurableInvitationRepository(
              pending: const [],
              accepted: [
                _acceptedPeople(id: 'Iaccepted1', invitedName: joinedName),
              ],
              pendingCount: 0,
            ),
          );

          await _pumpInvitesSegment(
            tester,
            locale: locale,
            screenCubit: screenCubit,
          );

          await tester.tap(find.text(l10n.friendsInvitesSegmentAccepted));
          await tester.pumpAndSettle();

          expect(
            find.text(l10n.friendsInviteAcceptedNewAccount(joinedName)),
            findsOneWidget,
          );
          expect(find.text(l10n.friendsInvitesPeopleSection), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'wire fetch maps a lone people pending invite onto the Pending list',
      (tester) async {
        await usePhoneSurface(tester);
        const name = 'Clara';
        final l10nRu = lookupL10n(const Locale('ru'));
        await tester.runAsync(() async {
          await withRemoteWire(
            {
              'InvitationTtl': {
                '__typename': 'query_root',
                'invitationTtlHours': 48,
              },
              'InvitationsFetchByUserId': _wireQueryRoot(
                pending: [
                  _wirePendingRow(id: 'Iabc123def456', addresseeName: name),
                ],
                accepted: const [],
                pendingCount: 1,
              ),
            },
            <WireSent>[],
            (remote) async {
              await _registerFriendsHarness(InvitationRepository(remote));
              await _pumpInvitesSegment(
                tester,
                locale: const Locale('ru'),
                screenCubit: screenCubit,
              );
              for (var i = 0; i < 80; i++) {
                await tester.pump(const Duration(milliseconds: 50));
                if (find.text(name).evaluate().isNotEmpty) break;
              }
              expect(find.text(name), findsOneWidget);
              expect(
                find.byTooltip(l10nRu.invitationAddresseeEditTitle),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
            },
          );
        });
      },
    );
  });
}
