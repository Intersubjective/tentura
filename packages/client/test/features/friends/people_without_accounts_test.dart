import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/friends/domain/use_case/friends_case.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/friends/ui/screen/friends_screen.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tag_screen.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tags_screen.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_field_wire_fixture.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/fake_block_case.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/mock_stack_router_scope.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart' show FakeContactsRepository;

const _annaId = 'PHanna0000001';
const _borisId = 'PHboris000001';
const _annaInvite = 'Ianna00000001';
const _borisInvite = 'Iboris0000001';
const _ordinaryInvite = 'Iclara0000001';
const _viewer = 'Uviewer000001';
const _fieldQuery = 'ConstellationFieldFetch';
const _invitationsQuery = 'InvitationsFetchByUserId';
const _heading = 'Not on Tentura yet';
const _ruHeading = 'Ещё не в Tentura';
const _neighbours = PersonTag(
  id: 'Tneighbours',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
  count: 1,
);
const _realMember = Profile(id: 'Uleo000000001', displayName: 'Leo');
const _ttl = {'__typename': 'query_root', 'invitationTtlHours': 7 * 24};

final _internalWord = RegExp('phantom|фантом', caseSensitive: false);
final _notInvited = RegExp(
  'not (yet )?invited|no (invite|invitation)|'
  '(invite|invitation) (not (yet )?sent|unsent)|'
  'не приглаш|без приглашения|приглашение (ещ[ёе] )?не отправлено',
  caseSensitive: false,
);

void main() {
  group('People who are not on Tentura yet', () {
    testWidgets('lists both active people with their own tags and invite status '
        'and hides the section when the Field has none', (tester) async {
      await _withPeopleScreen(tester, (screen) async {
        await screen.pump();
        expect(
          find.text(lookupL10n(const Locale('en')).friendsTitle),
          findsOneWidget,
        );
        expect(find.text(_heading), findsNothing);

        screen.people = [
          _anna(screen.now, inviteDaysAgo: 3),
          constellationPhantomWire(_borisId, 'Boris', now: screen.now),
        ];
        await screen.refreshField();
        // The snapshot stream can notify after the refresh helper pumps.
        await tester.pumpAndSettle();
        expect(
          [
            find.text(_heading),
            find.text('Anna K.'),
            find.text('Boris'),
            find.text(_neighbours.name),
            find.textContaining('invite sent 3 days ago'),
            find.textContaining(_notInvited),
          ].map((finder) => finder.evaluate().length),
          everyElement(1),
          reason:
              'The active Field entries should produce a heading, two names, '
              'Anna’s tag, a live invite age and a distinct uninvited status.',
        );
        final annaRow = _personRow(
          tester,
          find.text('Anna K.'),
          otherName: 'Boris',
        );
        final borisRow = _personRow(
          tester,
          find.text('Boris'),
          otherName: 'Anna K.',
        );
        expect(
          find.descendant(of: annaRow, matching: find.text(_neighbours.name)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: annaRow,
            matching: find.textContaining('invite sent 3 days ago'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: borisRow,
            matching: find.textContaining(_notInvited),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: borisRow,
            matching: find.textContaining('invite sent'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: borisRow, matching: find.text(_neighbours.name)),
          findsNothing,
        );
        expect(find.textContaining(_internalWord), findsNothing);
      });
    });

    testWidgets('shows the translated section heading on a narrow phone', (
      tester,
    ) async {
      await _withPeopleScreen(tester, (screen) async {
        screen.people = [_anna(screen.now)];
        await screen.refreshField();
        await screen.pump(locale: const Locale('ru'));

        expect(
          find.text(lookupL10n(const Locale('ru')).friendsTitle),
          findsOneWidget,
        );
        expect(find.text(_ruHeading).hitTestable(), findsOneWidget);
        expect(find.text('Anna K.'), findsOneWidget);
        expect(find.textContaining(_notInvited), findsOneWidget);
        expect(find.textContaining(_internalWord), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    test(
      'the People section heading is available in both language resources',
      () {
        Map<String, dynamic> messages(String language) =>
            jsonDecode(File('l10n/app_$language.arb').readAsStringSync())
                as Map<String, dynamic>;

        final en = messages('en');
        final ru = messages('ru');
        final headingKeys = [
          for (final entry in en.entries)
            if (!entry.key.startsWith('@') && entry.value == _heading)
              entry.key,
        ];
        expect(headingKeys, isNotEmpty);
        expect(headingKeys.map((key) => ru[key]), contains(_ruHeading));
        final englishKeys = en.keys.where((key) => !key.startsWith('@'));
        final russianKeys = ru.keys.where((key) => !key.startsWith('@'));
        expect(russianKeys, unorderedEquals(englishKeys));
        expect(
          [
            for (final key in englishKeys) en[key],
            for (final key in russianKeys) ru[key],
          ].whereType<String>().where(_internalWord.hasMatch),
          isEmpty,
        );
      },
    );

    testWidgets('Copy link copies the link for the selected row', (
      tester,
    ) async {
      final clipboard = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _withPeopleScreen(tester, (screen) async {
        screen.people = [
          constellationPhantomWire(_borisId, 'Boris', now: screen.now),
          _anna(screen.now),
        ];
        await screen.refreshField();
        await screen.pump();

        final anna = find.text('Anna K.');
        expect(anna, findsOneWidget);
        expect(find.text('Boris'), findsOneWidget);
        final copyLabel = find.textContaining(
          RegExp(r'^Copy (invite )?link$', caseSensitive: false),
        );
        expect(copyLabel, findsNWidgets(2));
        final annaCopy = find.descendant(
          of: _personRow(tester, anna, otherName: 'Boris'),
          matching: copyLabel,
        );
        expect(annaCopy, findsOneWidget);
        expect(screen.calls('PhantomInviteEnsure'), isEmpty);
        expect(clipboard, isEmpty);
        await tester.ensureVisible(annaCopy);
        await tester.tap(annaCopy);
        await _pumpUntil(tester, () => clipboard.isNotEmpty);

        expect(
          screen.calls('PhantomInviteEnsure').map((call) => call.variables),
          [
            {'id': _annaId},
          ],
        );
        expect(clipboard, [inviteShareUri(_annaInvite).toString()]);
        expect(Uri.parse(clipboard.single).path, '/invite/$_annaInvite');
      });
    });
  });

  group('Pending invitations for people without accounts', () {
    test(
      'Pending includes old personal links and excludes old ordinary and accepted links',
      () async {
        final sent = <WireSent>[];
        final now = DateTime.timestamp();
        final fresh = now.subtract(const Duration(days: 1));
        final old = now.subtract(const Duration(days: 8, hours: 1));
        final invites = [
          _inviteJson('Iexpired00001', old, name: 'Expired ordinary invite'),
          _inviteJson(_annaInvite, old, phantomId: _annaId),
          _inviteJson(_ordinaryInvite, fresh, name: 'Clara'),
          _inviteJson('Iclaimed00001', fresh, phantomId: _borisId)
            ..['invited_id'] = 'Ujoined000001'
            ..['accepted_at'] = now.toIso8601String(),
        ];
        late Map<String, ValueNode> whereByAlias;
        WireSent pendingRequest() =>
            sent.singleWhere((call) => call.operationName == _invitationsQuery);
        await withRemoteWire(
          {
            'InvitationTtl': _ttl,
            _invitationsQuery: _invitationQueryResult(
              pending: invites,
              pendingCount: invites.length,
            ),
          },
          sent,
          (remote) async {
            final repository = InvitationRepository(remote);
            addTearDown(repository.dispose);
            final result = await repository.fetchMine();
            expect(
              {
                'pending IDs': result.pending.map((row) => row.id).toList(),
                'pending count': result.pendingCount,
              },
              {
                'pending IDs': [_annaInvite, _ordinaryInvite],
                'pending count': 2,
              },
              reason:
                  'Apply the sent list and aggregate filters to the same '
                  'fresh, expired and accepted invitation records.',
            );

            final call = pendingRequest();
            final cutoff = call.variables.entries.singleWhere(
              (entry) =>
                  entry.value is String &&
                  DateTime.tryParse(entry.value as String) != null,
            );
            final expected = unorderedEquals([
              {
                'invited_id': {'_is_null': true},
              },
              {
                '_or': unorderedEquals([
                  {
                    'created_at': {'_gt': '\$${cutoff.key}'},
                  },
                  {
                    'phantom_id': {'_is_null': false},
                  },
                ]),
              },
            ]);
            expect(
              whereByAlias.map(
                (alias, where) => MapEntry(alias, _andPredicates(where)),
              ),
              {
                'pending': expected,
                'pending_count': expected,
              },
            );
          },
          selectResponse: (query, data) {
            if (!data.containsKey('pending')) return data;
            final operation = parseString(
              query,
            ).definitions.whereType<OperationDefinitionNode>().single;
            whereByAlias = {
              for (final field
                  in operation.selectionSet.selections.whereType<FieldNode>())
                if (field.alias?.value case 'pending' || 'pending_count')
                  field.alias!.value: field.arguments
                      .singleWhere((arg) => arg.name.value == 'where')
                      .value,
            };
            final variables = pendingRequest().variables;
            Iterable<Map<String, dynamic>> matching(String alias) {
              final filter =
                  _value(whereByAlias[alias]!) as Map<String, Object?>;
              return invites.where(
                (row) => _matchesWhere(filter, row, variables),
              );
            }

            return _invitationQueryResult(
              pending: matching('pending').toList(),
              pendingCount: matching('pending_count').length,
            );
          },
        );
      },
    );

    test(
      'the invitation fragment requests the linked person id and the repository delivers it',
      () async {
        final fixture = _PeopleWire()..includeInvites = true;
        final fragmentFields = <String>[];
        await withRemoteWire(
          const {},
          fixture.sent,
          (remote) async {
            final repository = InvitationRepository(remote);
            addTearDown(repository.dispose);
            final result = await repository.fetchMine();
            expect(result.pending.map((row) => row.id), [
              _annaInvite,
              _ordinaryInvite,
            ]);
            expect(result.pending.first.addresseeName, isNull);
            expect(
              {
                'selectsLinkedPerson': fragmentFields.contains('phantom_id'),
                'linkedPersonIds': result.pending
                    .map((row) => row.phantomId)
                    .toList(),
              },
              {
                'selectsLinkedPerson': true,
                'linkedPersonIds': [_annaId, null],
              },
            );
          },
          responseFor: fixture.respond,
          selectResponse: (query, data) {
            if (!data.containsKey('pending')) return data;
            final fragment = parseString(query).definitions
                .whereType<FragmentDefinitionNode>()
                .singleWhere((node) => node.name.value == 'InvitationRow');
            fragmentFields.addAll(
              fragment.selectionSet.selections.whereType<FieldNode>().map(
                (node) => node.name.value,
              ),
            );
            if (fragmentFields.contains('phantom_id')) return data;
            return {
              ...data,
              'pending': [
                for (final row in data['pending'] as List<Map<String, dynamic>>)
                  {...row}..remove('phantom_id'),
              ],
            };
          },
        );
      },
    );

    testWidgets('Pending counts and names an older personal invite and a fresh '
        'ordinary invite without showing an expiry for the personal link', (
      tester,
    ) async {
      await _withInvites(tester, (screen) async {
        final pending = find.byKey(const ValueKey('invites-segment-pending'));
        final pendingCount = find.descendant(
          of: pending,
          matching: find.textContaining(RegExp(r'\b2\b')),
          matchRoot: true,
        );

        expect(_invitesTab(screen.l10n, 2), findsOneWidget);
        expect(find.text('Clara'), findsOneWidget);
        expect(
          (
            named: find.text('Anna K.').evaluate().length,
            untitled: find
                .text(screen.l10n.friendsInvitePendingUntitled)
                .evaluate()
                .length,
            count: pendingCount.evaluate().length,
          ),
          (named: 1, untitled: 0, count: 1),
        );
        expect(
          find.descendant(
            of: _linkedInviteRow(tester),
            matching: find.textContaining(
              RegExp(
                'expir|valid (for|until)|days? left',
                caseSensitive: false,
              ),
            ),
          ),
          findsNothing,
        );
        expect(find.textContaining(_internalWord), findsNothing);
      });
    });

    testWidgets('opening a personal invite shows the person panel while an '
        'ordinary invite opens the share dialog', (tester) async {
      await _withInvites(tester, (screen) async {
        await tester.tap(find.text('Clara'));
        await tester.pumpAndSettle();
        expect(find.byType(ShareCodeDialog), findsOneWidget);
        Navigator.of(tester.element(find.byType(ShareCodeDialog))).pop();
        await tester.pumpAndSettle();

        await tester.tap(_linkedInviteTitle());
        await tester.pumpAndSettle();

        expect(
          (
            status: find
                .text('$_heading · invite sent 8 days ago')
                .evaluate()
                .length,
            shareDialogs: find.byType(ShareCodeDialog).evaluate().length,
          ),
          (status: 1, shareDialogs: 0),
        );
        expect(find.text('Anna K.'), findsWidgets);
        expect(find.textContaining(_internalWord), findsNothing);
      });
    });

    testWidgets('deleting the pending link keeps the person and changes their '
        'status to uninvited', (tester) async {
      await _withInvites(tester, (screen) async {
        await tester.tap(
          find.descendant(
            of: _linkedInviteRow(tester),
            matching: find.byTooltip(screen.l10n.buttonDelete),
          ),
        );
        await tester.pumpAndSettle();
        final confirm = find.text(screen.l10n.buttonRemoveInvite);
        expect(confirm, findsOneWidget);
        await tester.tap(confirm);

        await _pumpUntil(
          tester,
          () => _invitesTab(screen.l10n, 1).evaluate().isNotEmpty,
        );
        expect(
          screen.calls('InvitationDeleteById').map((call) => call.variables),
          [
            {'id': _annaInvite},
          ],
        );
        expect(screen.calls('PhantomDelete'), isEmpty);
        expect(_linkedInviteTitle(), findsNothing);
        expect(find.text('Clara'), findsOneWidget);

        await tester.tap(find.widgetWithText(Tab, screen.l10n.friendsTitle));
        await tester.pumpAndSettle();
        await _pumpUntil(
          tester,
          () => find.textContaining(_notInvited).evaluate().isNotEmpty,
        );
        expect(find.text(_heading), findsOneWidget);
        expect(find.text('Anna K.'), findsOneWidget);
        expect(find.textContaining(_notInvited), findsOneWidget);
        expect(find.textContaining('invite sent'), findsNothing);
      });
    });
  });

  testWidgets('opening a tag in the manager lists its members with and '
      'without accounts', (tester) async {
    await _withPeopleScreen(tester, (screen) async {
      screen.people = [
        _anna(screen.now),
        constellationPhantomWire(_borisId, 'Boris', now: screen.now),
      ];
      await screen.refreshField();

      final router = RootStackRouter.build(
        routes: [
          AutoRoute(
            page: PeopleTagsRoute.page,
            path: kPathPeopleTags,
            initial: true,
          ),
          AutoRoute(page: PeopleTagRoute.page, path: kPathPeopleTag),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router.config(),
          builder: (_, child) =>
              TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PeopleTagsScreen), findsOneWidget);
      expect(find.byType(PeopleTagScreen), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, _neighbours.name));
      await tester.pumpAndSettle();

      final detailScreen = find.byType(PeopleTagScreen);
      expect(detailScreen, findsOneWidget);
      expect(
        tester.widget<PeopleTagScreen>(detailScreen).tagId,
        _neighbours.id,
      );
      final memberList = find.descendant(
        of: detailScreen,
        matching: find.byType(ListView),
      );
      expect(memberList, findsOneWidget);
      Finder memberRow(String name) => find.descendant(
        of: memberList,
        matching: find.widgetWithText(ListTile, name),
      );
      expect(memberRow('Leo'), findsOneWidget);
      expect(memberRow('Boris'), findsNothing);
      expect(memberRow('Anna K.'), findsOneWidget);
      expect(find.textContaining(_internalWord), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Scope each person's text and actions to the subtree before the next row.
Finder _personRow(
  WidgetTester tester,
  Finder name, {
  required String otherName,
}) {
  Element? row;
  tester.element(name).visitAncestorElements((ancestor) {
    final otherPerson = find.descendant(
      of: find.byElementPredicate((element) => identical(element, ancestor)),
      matching: find.text(otherName),
    );
    if (otherPerson.evaluate().isNotEmpty) return false;
    row = ancestor;
    return true;
  });
  expect(row, isNotNull, reason: 'The two names must render in separate rows.');
  return find.byElementPredicate((element) => identical(element, row));
}

Finder _invitesTab(L10n l10n, int count) =>
    find.text('${l10n.invitationScreenTitle} ($count)');

Finder _linkedInviteTitle() {
  final name = find.text('Anna K.');
  return name.evaluate().isNotEmpty
      ? name
      : find.text(lookupL10n(const Locale('en')).friendsInvitePendingUntitled);
}

Finder _linkedInviteRow(WidgetTester tester) =>
    _personRow(tester, _linkedInviteTitle(), otherName: 'Clara');

Future<void> _withInvites(
  WidgetTester tester,
  Future<void> Function(_PeopleScreen) exercise,
) => _withPeopleScreen(tester, (screen) async {
  screen.includeInvites = true;
  screen.people = [_anna(screen.now, inviteDaysAgo: 8)];
  await screen.refreshField();
  await screen.pump(
    child: const FriendsScreen(initialTab: kHomeTabInvitations),
  );
  final ordinaryInvite = find.text('Clara');
  await _pumpUntil(tester, () => ordinaryInvite.evaluate().isNotEmpty);
  expect(
    ordinaryInvite,
    findsOneWidget,
    reason:
        'Invitations should render the served ordinary row. Calls: '
        '${screen.sent.map((call) => call.operationName).toList()}. '
        'Visible text: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().toList()}.',
  );
  await exercise(screen);
});

Future<void> _withPeopleScreen(
  WidgetTester tester,
  Future<void> Function(_PeopleScreen) exercise,
) async {
  await usePhoneSurface(tester);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = kPhoneSurface;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.runAsync(() async {
    final screen = _PeopleScreen(tester);
    await withRemoteWire(
      const {},
      screen.sent,
      (remote) async {
        final realtime = buildTestRealtimeSync();
        final invitations = InvitationRepository(remote);
        final tagsRepository = FakePeopleTagsRepository(
          tagList: [_neighbours],
          memberList: [
            const PersonTagMembers(
              tagId: 'Tneighbours',
              personIds: ['Uleo000000001'],
            ),
          ],
        );
        final tags = await PeopleTagsTestRig.create(tagsRepository);
        final auth = buildTestAuthCase(_SignedInAuthLocal(), EmptyAuthRemote());
        final contacts = ContactsCase(
          FakeContactsRepository(),
          auth,
          ContactNameStore(),
          realtime.case_,
          env: const Env(),
          logger: Logger('PeopleContactsTest'),
        );
        final effects = FakeUiEffectPort();
        screen.screenCubit = ScreenCubit.local(effects);
        screen.field = ConstellationFieldStoreCase(
          ConstellationRepository(remote),
          const _FieldAccount(),
          FakeClockPort(screen.now),
          FakeWakeUpPort(),
          realtime.case_,
          env: const Env(),
          logger: Logger('PeopleFieldTest'),
          phantomsEnabled: true,
        );
        final lease = screen.field.lease();
        registerFakeAppNavigator();
        GetIt.I
          ..registerSingleton<AuthCase>(auth)
          ..registerSingleton<FriendsCubit>(_ReadyFriends())
          ..registerSingleton<FriendsCase>(
            FriendsCase(
              _UnusedCapabilities(),
              invitations,
              _UnusedLikes(),
              _UnusedFriendsRemote(),
              _UnusedPresence(),
              contacts,
              auth,
              realtime.case_,
              FakeBlockCase(),
            ),
          )
          ..registerSingleton<InvitationRepository>(invitations)
          ..registerSingleton<ConstellationFieldStoreCase>(screen.field)
          ..registerSingleton<PeopleTagsCase>(tags.peopleTags)
          ..registerSingleton<PeopleTagsRepositoryPort>(tagsRepository)
          ..registerSingleton<ProfileRepositoryPort>(_Profiles())
          ..registerSingleton<PhantomRepositoryPort>(PhantomRepository(remote))
          ..registerSingleton<UiEffectPort>(effects);
        try {
          await screen.refreshField();
          await exercise(screen);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await screen.screenCubit.close();
          await GetIt.I.reset();
          lease.dispose();
          await screen.field.dispose();
          await invitations.dispose();
          await tags.dispose();
          await realtime.port.dispose();
        }
      },
      responseFor: screen.respond,
    );
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 25 && !ready(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

class _PeopleScreen extends _PeopleWire {
  _PeopleScreen(this.tester);

  final WidgetTester tester;
  late final ConstellationFieldStoreCase field;
  late final ScreenCubit screenCubit;
  L10n get l10n => lookupL10n(const Locale('en'));

  Future<void> refreshField() async {
    await field
        .requestRefresh(ConstellationRefreshReason.load)
        .timeout(const Duration(seconds: 3));
    expect(
      field.current.field?.phantoms.map((person) => person.id),
      people.map((person) => person['id']),
      reason: 'The Field fixture must reach the actual snapshot store.',
    );
    await tester.pump();
  }

  Future<void> pump({
    Locale locale = const Locale('en'),
    Widget child = const FriendsScreen(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: wrapWithMockStackRouter(
          TenturaResponsiveScope(
            child: BlocProvider<ScreenCubit>.value(
              value: screenCubit,
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

class _PeopleWire {
  // Stay clear of an integer age boundary across real and fake widget clocks.
  final now = DateTime.timestamp();
  final sent = <WireSent>[];
  List<Map<String, dynamic>> people = [];
  bool includeInvites = false;
  bool inviteDeleted = false;

  Iterable<WireSent> calls(String operation) =>
      sent.where((call) => call.operationName == operation);

  Future<Map<String, dynamic>> respond(WireSent call) async {
    switch (call.operationName) {
      case _fieldQuery:
        return constellationFieldWire(
          now: now,
          viewerId: _viewer,
          phantoms: people,
        );
      case 'InvitationTtl':
        return _ttl;
      case _invitationsQuery:
        final rows = [
          if (includeInvites && !inviteDeleted)
            _inviteJson(
              _annaInvite,
              now.subtract(const Duration(days: 8, hours: 1)),
              phantomId: _annaId,
            ),
          if (includeInvites)
            _inviteJson(
              _ordinaryInvite,
              now.subtract(const Duration(days: 1)),
              name: 'Clara',
            ),
        ];
        return _invitationQueryResult(
          pending: rows
              .skip(call.variables['pending_offset'] as int? ?? 0)
              .take(call.variables['pending_limit'] as int? ?? rows.length)
              .toList(),
          pendingCount: rows.length,
        );
      case 'InvitationDeleteById':
        if (call.variables['id'] != _annaInvite) {
          return {'invitationDelete': false};
        }
        inviteDeleted = true;
        people = [_anna(now)];
        return {'invitationDelete': true};
      case 'PhantomInviteEnsure':
        return {
          'phantomInviteEnsure': switch (call.variables['id']) {
            _annaId => _annaInvite,
            _borisId => _borisInvite,
            final id => throw StateError('Unexpected person id: $id'),
          },
        };
      case 'PhantomDelete':
        people = [];
        return {'phantomDelete': true};
      default:
        throw StateError('Unexpected operation ${call.operationName}');
    }
  }
}

Map<String, dynamic> _invitationQueryResult({
  required List<Map<String, dynamic>> pending,
  required int pendingCount,
}) => {
  '__typename': 'query_root',
  'pending': pending,
  'accepted': <Object?>[],
  'pending_count': {
    '__typename': 'invitation_aggregate',
    'aggregate': {
      '__typename': 'invitation_aggregate_fields',
      'count': pendingCount,
    },
  },
};

Map<String, dynamic> _anna(DateTime now, {int? inviteDaysAgo}) =>
    constellationPhantomWire(
      _annaId,
      'Anna K.',
      now: now,
      tags: [_neighbours.id],
      inviteDaysAgo: inviteDaysAgo,
    );

Map<String, dynamic> _inviteJson(
  String id,
  DateTime createdAt, {
  String? name,
  String? phantomId,
}) => {
  '__typename': 'invitation',
  'id': id,
  'beacon_id': null,
  'invited_id': null,
  'addressee_name': name,
  'invite_origin': null,
  'accepted_at': null,
  'created_at': createdAt.toIso8601String(),
  'updated_at': createdAt.toIso8601String(),
  'invited': null,
  'beacon': null,
  'phantom_id': phantomId,
};

/// Apply the boolean operators used by the Hasura invitation query to one
/// fixture row. Run this separately for the list and the count.
bool _matchesWhere(
  Map<String, Object?> filter,
  Map<String, dynamic> row,
  Map<String, dynamic> variables,
) {
  bool matchesTerm(Object? term) => switch (term) {
    final Map<String, Object?> expression => _matchesWhere(
      expression,
      row,
      variables,
    ),
    _ => throw StateError('Expected an invitation predicate, got $term'),
  };

  return filter.entries.every(
    (entry) => switch ((entry.key, entry.value)) {
      ('_and', final Map<String, Object?> term) => matchesTerm(term),
      ('_and', final List<Object?> terms) => terms.every(matchesTerm),
      ('_or', final List<Object?> terms) => terms.any(matchesTerm),
      (final column, {'_is_null': final bool isNull}) =>
        (row[column] == null) == isNull,
      (final column, {'_gt': final String variable}) =>
        DateTime.parse(row[column] as String).isAfter(
          DateTime.parse(variables[variable.substring(1)] as String),
        ),
      _ => throw StateError('Unsupported invitation predicate: $entry'),
    },
  );
}

List<Object?> _andPredicates(ValueNode where) {
  final fields = _value(where) as Map<String, Object?>;
  return [
    for (final entry in fields.entries)
      if (entry.key != '_and')
        {entry.key: entry.value}
      else if (entry.value case final List<Object?> terms)
        ...terms
      else if (entry.value case final Map<String, Object?> terms)
        for (final term in terms.entries) {term.key: term.value},
  ];
}

Object _value(ValueNode value) => switch (value) {
  ObjectValueNode(:final fields) => {
    for (final field in fields) field.name.value: _value(field.value),
  },
  ListValueNode(:final values) => values.map(_value).toList(),
  BooleanValueNode(:final value) => value,
  VariableNode(:final name) => '\$${name.value}',
  _ => throw StateError(
    'Unexpected pending filter value: ${value.runtimeType}',
  ),
};

class _ReadyFriends extends Mock implements FriendsCubit {
  @override
  FriendsState get state =>
      const FriendsState(friends: {}, firstLoadDone: true);

  @override
  Stream<FriendsState> get stream => const Stream.empty();
}

class _SignedInAuthLocal extends EmptyAuthLocal {
  @override
  Stream<String> currentAccountChanges() => Stream.value(_viewer);
}

class _FieldAccount implements ConstellationAccountPort {
  const _FieldAccount();

  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewer);
}

class _Profiles extends Fake implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    if (ids.contains(_realMember.id)) _realMember,
  ];
}

class _UnusedCapabilities extends Fake implements CapabilityRepositoryPort {}

class _UnusedLikes extends Fake implements LikeRemoteRepository {}

class _UnusedFriendsRemote extends Fake implements FriendsRemoteRepository {}

class _UnusedPresence extends Fake implements PresenceRepository {}
