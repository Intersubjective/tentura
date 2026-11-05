import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/friends/domain/entity/person_list_meta.dart';
import 'package:tentura/features/friends/domain/people_list_order.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/friends/ui/widget/people_list_pane.dart';
import 'package:tentura/features/friends/ui/widget/people_ordered_list.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

Profile _person(
  String id, {
  String name = '',
  DateTime? lastSeen,
}) => Profile(
  id: id,
  displayName: name.isEmpty ? id : name,
  presenceLastSeenAt: lastSeen,
);

class _PaneFriendsCubit extends Mock implements FriendsCubit {
  _PaneFriendsCubit(this._state);

  final FriendsState _state;

  @override
  FriendsState get state => _state;

  @override
  Stream<FriendsState> get stream => Stream<FriendsState>.value(_state);
}

class _ViewerCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

void main() {
  group('buildPeopleListSections', () {
    final t0 = DateTime.utc(2026, 11, 5, 12);
    final t1 = DateTime.utc(2026, 11, 4, 12);
    final t2 = DateTime.utc(2026, 11, 3, 12);

    test('New section is newest first with distinct reasons', () {
      final friends = {
        'a': _person('a', name: 'Anna'),
        'b': _person('b', name: 'Boris'),
        'c': _person('c', name: 'Cecilia'),
      };
      final meta = {
        'a': PersonListMeta(
          id: 'a',
          newSince: t1,
          newReason: PersonNewReason.invite,
        ),
        'b': PersonListMeta(
          id: 'b',
          newSince: t2,
          newReason: PersonNewReason.trusted,
        ),
        'c': PersonListMeta(
          id: 'c',
          newSince: t0,
          newReason: PersonNewReason.mutual,
        ),
      };
      final sections = buildPeopleListSections(
        friends: friends,
        listMeta: meta,
      );
      expect(sections.newPeople.map((p) => p.id), ['c', 'a', 'b']);
      expect(sections.rest, isEmpty);
    });

    test('Nobody appears in both New and the main list', () {
      final friends = {
        'new': _person('new', name: 'New'),
        'old': _person('old', name: 'Old'),
      };
      final meta = {
        'new': PersonListMeta(
          id: 'new',
          newSince: t0,
          newReason: PersonNewReason.trusted,
          lastInteractionAt: t0,
        ),
        'old': PersonListMeta(
          id: 'old',
          lastInteractionAt: t1,
        ),
      };
      final sections = buildPeopleListSections(
        friends: friends,
        listMeta: meta,
      );
      expect(sections.newPeople.single.id, 'new');
      expect(sections.rest.single.id, 'old');
    });

    test('Main list orders by interaction, then last seen, then name', () {
      final seenRecent = DateTime.utc(2026, 11, 5, 8);
      final seenOlder = DateTime.utc(2026, 11, 1, 8);
      final friends = {
        'zara': _person('zara', name: 'Zara', lastSeen: seenOlder),
        'mike': _person('mike', name: 'Mike', lastSeen: seenRecent),
        'amy': _person('amy', name: 'Amy'),
        'boris': _person('boris', name: 'Boris'),
      };
      final meta = {
        'amy': PersonListMeta(
          id: 'amy',
          lastInteractionAt: DateTime.utc(2026, 11, 5, 10),
        ),
        'boris': PersonListMeta(
          id: 'boris',
          lastInteractionAt: DateTime.utc(2026, 11, 4, 10),
        ),
        'mike': const PersonListMeta(id: 'mike'),
        'zara': const PersonListMeta(id: 'zara'),
      };
      final sections = buildPeopleListSections(
        friends: friends,
        listMeta: meta,
      );
      expect(sections.newPeople, isEmpty);
      expect(sections.rest.map((p) => p.id), ['amy', 'boris', 'mike', 'zara']);
    });

    test('Optimistic local trust puts a person at the top of New', () {
      final friends = {'x': _person('x', name: 'Xena')};
      final now = DateTime.utc(2026, 11, 5, 16);
      final sections = buildPeopleListSections(
        friends: friends,
        listMeta: const {},
        optimisticNew: {
          'x': PersonListMeta(
            id: 'x',
            newSince: now,
            newReason: PersonNewReason.trusted,
          ),
        },
      );
      expect(sections.newPeople.single.id, 'x');
    });
  });

  group('PeopleOrderedList widget', () {
    setUp(() async {
      await initializeDateFormatting('ru');
      RelativeTimestampTicker.debugClock = () => DateTime.utc(2026, 11, 5, 15);
    });
    tearDown(() => RelativeTimestampTicker.debugClock = null);

    testWidgets('RU phone shows New reasons and hides empty section', (
      tester,
    ) async {
      final now = RelativeTimestampTicker.now();
      final inviteAt = now.subtract(const Duration(days: 2));
      final trustedAt = now.subtract(const Duration(days: 5));
      await usePhoneSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: _ViewerCubit()),
                BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                BlocProvider<ScreenCubit>.value(
                  value: ScreenCubit.local(FakeUiEffectPort()),
                ),
              ],
              child: Scaffold(
                body: SingleChildScrollView(
                  child: PeopleOrderedList(
                    friends: {
                      'inv': _person('inv', name: 'Анна К.'),
                      'tr': _person('tr', name: 'Борис'),
                      'rest': _person('rest', name: 'Дмитрий'),
                    },
                    friendContexts: const {},
                    listMeta: {
                      'inv': PersonListMeta(
                        id: 'inv',
                        newSince: inviteAt,
                        newReason: PersonNewReason.invite,
                      ),
                      'tr': PersonListMeta(
                        id: 'tr',
                        newSince: trustedAt,
                        newReason: PersonNewReason.trusted,
                      ),
                      'rest': PersonListMeta(
                        id: 'rest',
                        lastInteractionAt: now.subtract(
                          const Duration(hours: 3),
                        ),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final l10n = lookupL10n(const Locale('ru'));
      expect(find.text(l10n.friendsPeopleSectionNew), findsOneWidget);
      expect(
        find.text(
          l10n.friendsPeopleNewReasonInvite(l10n.relativeTimeDaysAgo(2)),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.friendsPeopleNewReasonTrusted(l10n.relativeTimeDaysAgo(5)),
        ),
        findsOneWidget,
      );
      expect(find.text('Дмитрий'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PeopleListPane uses the same ordered list', (tester) async {
      final state = FriendsState(
        friends: {
          'n': _person('n', name: 'Nova'),
          'r': _person('r', name: 'Rest'),
        },
        listMeta: {
          'n': PersonListMeta(
            id: 'n',
            newSince: DateTime.utc(2026, 11, 5),
            newReason: PersonNewReason.trusted,
          ),
          'r': const PersonListMeta(id: 'r'),
        },
        firstLoadDone: true,
      );
      final cubit = _PaneFriendsCubit(state);
      GetIt.I.registerSingleton<FriendsCubit>(cubit);
      addTearDown(() => GetIt.I.unregister<FriendsCubit>());
      await usePhoneSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: _ViewerCubit()),
                BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                BlocProvider<ScreenCubit>.value(
                  value: ScreenCubit.local(FakeUiEffectPort()),
                ),
              ],
              child: const PeopleListPane(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('New'), findsOneWidget);
      final nova = find.text('Nova');
      final rest = find.text('Rest');
      expect(tester.getTopLeft(nova).dy < tester.getTopLeft(rest).dy, isTrue);
    });
  });

  test('FriendsRemoteRepository maps PeopleListMetaFetch wire rows', () async {
    final sent = <WireSent>[];
    final at = DateTime.utc(2026, 11, 2, 9, 30);
    late Map<String, PersonListMeta> mapped;
    await withRemoteWire(
      {
        'PeopleListMetaFetch': {
          'peopleListMeta': [
            {
              '__typename': 'v2_PersonListMeta',
              'id': 'Ufriend000001',
              'newSince': at.toIso8601String(),
              'newReason': 'invite',
              'lastInteractionAt': at.toIso8601String(),
            },
          ],
        },
      },
      sent,
      (remote) async {
        final repo = FriendsRemoteRepository(
          remoteApiService: remote,
          log: Logger('test'),
        );
        mapped = await repo.fetchPeopleListMeta();
      },
    );
    expect(sent.single.operationName, 'PeopleListMetaFetch');
    expect(mapped['Ufriend000001']!.newReason, PersonNewReason.invite);
    expect(mapped['Ufriend000001']!.newSince, at);
    expect(mapped['Ufriend000001']!.lastInteractionAt, at);
  });
}
