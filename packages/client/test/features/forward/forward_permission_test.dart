import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart'
    show ForwardBeaconRoute, RootRouter;
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/graph_trust_write_fixture.dart'
    show CountingProfileRepository;
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_screen_harness.dart';
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import '../contacts/contacts_case_test.dart'
    show FakeContactsRepository, StreamingAuthLocal;
import '../post_view/issue_1239_archived_post_forward_gating_test.dart'
    show openPostInfoSheet, pumpLivePostForForwardPermission;

const _postId = 'Bparentpost01';
const _author = Profile(id: 'Uauthor', displayName: 'Author');
const _reader = Profile(id: 'Ureader', displayName: 'Reader');
final _createdAt = DateTime.utc(2026, 10, 20, 12);

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _reader);

  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

const _requestId = 'Brequest00001';
const _requestPath = '$kPathBeaconView/$_requestId';
const _expectedForwardPath = '/forward/$_requestId';
const _requestTitle = 'Bring a ladder';
const _recipientName = 'Clara Recipient';

const _emptyHelpOffers = {
  '__typename': 'beacon_help_offer_aggregate',
  'aggregate': null,
};

final _englishDenial = RegExp(
  r"^(?=.*\brequest\b)(?=.*\bforward)(?=.*(?:can['’]t|cannot|can not|not allowed|no permission|don['’]t have permission)).*",
  caseSensitive: false,
);
final _russianDenial = RegExp(
  '^(?=.*запрос)(?=.*перес[ыл])(?=.*(?:не мож|нельзя|невозможно|не уда[её]тся|нет прав|недоступ)).*',
  caseSensitive: false,
  unicode: true,
);

Map<String, dynamic> _requestRead({
  required bool canForward,
  required bool canReadInvolvement,
  required int accessLevel,
  required int accessReasons,
  String? parentPostId,
  int forwardPolicy = 1,
}) => {
  '__typename': 'query_root',
  'beacon_by_pk': {
    '__typename': 'beacon',
    'viewer_can_forward': canForward,
    'cover_source': 0,
    'needs': '',
    'created_at': _createdAt.toIso8601String(),
    'updated_at': _createdAt.toIso8601String(),
    'status': 0,
    'tags': '',
    'beacon_images': <Object>[],
    'help_offers_aggregate': _emptyHelpOffers,
    'unanswered_help_offers': _emptyHelpOffers,
    'admitted_helpers_aggregate': _emptyHelpOffers,
    'is_discoverable': true,
    'id': _requestId,
    'title': _requestTitle,
    'description': '',
    'author': {
      '__typename': 'user',
      'id': _author.id,
      'display_name': _author.displayName,
      'description': '',
    },
    'kind': 0,
    'forward_policy': forwardPolicy,
    'post_draft_attachments': <Object>[],
    'active_help_offers': <Object>[],
    'participant_help_offers': <Object>[],
    'admitted_helpers': <Object>[],
    'lineage_parent_beacon_id': parentPostId,
    'can_read_content': true,
    'can_read_involvement': canReadInvolvement,
    'access_level': accessLevel,
    'access_reasons': accessReasons,
  },
};

Future<BeaconViewCubit> _loadRequestFromWire(
  WidgetTester tester, {
  required bool canForward,
  required Profile viewer,
  required int accessLevel,
  required int accessReasons,
  required bool canReadInvolvement,
  String? parentPostId,
}) async {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final sent = <WireSent>[];
  late BeaconViewCubit cubit;
  await tester.runAsync(() async {
    await withRemoteWire(
      {
        'BeaconFetchById': _requestRead(
          canForward: canForward,
          canReadInvolvement: canReadInvolvement,
          accessLevel: accessLevel,
          accessReasons: accessReasons,
          parentPostId: parentPostId,
        ),
      },
      sent,
      (remote) async {
        cubit = BeaconViewCubit(
          id: _requestId,
          myProfile: viewer,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: BeaconRepository(remote, realtime.port),
            realtimeSyncCase: realtime.case_,
          ),
          effects: FakeUiEffectPort(),
        );
        if (!cubit.state.firstLoadDone) {
          await cubit.stream
              .firstWhere((state) => state.firstLoadDone)
              .timeout(const Duration(seconds: 5));
        }
      },
    );
  });
  addTearDown(() => tester.runAsync(cubit.close));
  expect(cubit.state.firstLoadDone, isTrue);
  expect(
    sent
        .where((call) => call.operationName == 'BeaconFetchById')
        .single
        .variables,
    {'id': _requestId},
  );
  return cubit;
}

Future<void> _openRequestFromWire(
  WidgetTester tester, {
  required bool canForward,
  required bool canReadInvolvement,
  required Profile viewer,
  required int accessLevel,
  required int accessReasons,
  required Locale locale,
  String? parentPostId,
}) async {
  final cubit = await _loadRequestFromWire(
    tester,
    canForward: canForward,
    canReadInvolvement: canReadInvolvement,
    viewer: viewer,
    accessLevel: accessLevel,
    accessReasons: accessReasons,
    parentPostId: parentPostId,
  );
  final host = beaconViewHarnessHost(beaconId: _requestId);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    final closing = host.close();
    await tester.pump();
    await closing;
    await unregisterBeaconViewHarnessGetIt();
  });
  await pumpBeaconViewHarness(
    tester,
    size: locale.languageCode == 'ru'
        ? kPhoneSurface
        : kBeaconViewHarnessExpanded,
    locale: locale,
    beaconState: cubit.state,
    beaconViewCubit: cubit,
    threadsState: beaconViewHarnessThreadsState(authorId: viewer.id),
    host: host,
  );
  await tester.pumpAndSettle();
  expect(find.byType(BeaconViewScreen), findsOneWidget);
  expect(find.text(_requestTitle), findsWidgets);
}

class _ForwardContext extends Mock implements ContextCubit {
  @override
  ContextState get state => const ContextState();

  @override
  Stream<ContextState> get stream => const Stream.empty();
}

const _involvementDenial = 'Viewer cannot read request involvement';

const _candidateRead = {
  '__typename': 'query_root',
  'forwardCandidates': [
    {
      '__typename': 'v2_user',
      'id': 'Urecipient001',
      'displayName': _recipientName,
      'description': '',
      'my_vote': 1,
      'trusts_viewer': true,
      'is_mutual_friend': true,
      'shares_active_context': false,
      'scores': <Object>[],
    },
  ],
};

const _involvementRead = {
  '__typename': 'query_root',
  'beaconInvolvement': {
    '__typename': 'v2_BeaconInvolvement',
    'forwardedToIds': <String>[],
    'helpOfferedIds': <String>[],
    'withdrawnIds': <String>[],
    'rejectedIds': <String>[],
    'watchingIds': <String>[],
    'onwardForwarderIds': <String>[],
    'declinedOfferIds': <String>[],
    'myForwardedRecipients': <Object>[],
  },
};

class _ForwardRouteAuth extends Fake implements AuthCubit {
  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _ForwardRouteSettings extends Fake implements SettingsCubit {
  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

/// Uses production Forward routing and AppNavigator, with only the surrounding
/// Request route scope supplied by the test.
class _ForwardTestRouter extends RootRouter {
  _ForwardTestRouter(this.requestPage)
    : super(
        Logger('ForwardTestRouter'),
        _ForwardRouteAuth(),
        _ForwardRouteSettings(),
        PostJoinNavigationCubit(),
      );

  final Widget? requestPage;

  @override
  List<AutoRoute> get routes => [
    if (requestPage case final page?)
      NamedRouteDef(
        name: 'RequestFixtureRoute',
        path: '$kPathBeaconView/:id',
        builder: (_, _) => page,
      ),
    super.routes.singleWhere(
      (route) => route.page.name == ForwardBeaconRoute.name,
    ),
  ];
}

Future<void> _pumpForwardRoutes(
  WidgetTester tester, {
  required Locale locale,
  required bool canForward,
  bool canReadInvolvement = true,
  Widget? requestPage,
  Future<void> Function(RootRouter)? verifyNavigation,
}) async {
  final getIt = GetIt.I;
  final auth = StreamingAuthLocal(_reader.id);
  final realtime = buildTestRealtimeSync();
  final contactsStore = ContactNameStore();
  final contacts = ContactsCase(
    FakeContactsRepository(),
    buildTestAuthCase(auth, EmptyAuthRemote()),
    contactsStore,
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  addTearDown(() async {
    await contacts.dispose();
    await contactsStore.dispose();
    await auth.dispose();
    await realtime.port.dispose();
  });
  final sent = <WireSent>[];
  final fromPost = requestPage != null || !canReadInvolvement;
  await withRemoteWire(
    {
      'BeaconFetchById': _requestRead(
        canForward: canForward,
        canReadInvolvement: canReadInvolvement,
        accessLevel: 2,
        accessReasons: fromPost ? 64 : 32,
        parentPostId: fromPost ? _postId : null,
        forwardPolicy: canReadInvolvement && !canForward ? 0 : 1,
      ),
      'ForwardCandidatesFetch': _candidateRead,
      'BeaconInvolvementData': _involvementRead,
      if (fromPost)
        'BeaconLineageForwardSuggestions': {
          '__typename': 'query_root',
          'beaconLineageForwardSuggestions': {
            '__typename': 'v2_BeaconLineageForwardSuggestions',
            'sourceBeaconId': _postId,
            'rootBeaconId': _postId,
            'suggestedNote': '',
            'suggestions': <Object>[],
          },
        },
    },
    sent,
    errors: {
      if (!canReadInvolvement)
        'BeaconInvolvementData': {
          'message': _involvementDenial,
          'extensions': {'code': '1102'},
        },
    },
    (remote) async {
      final beacons = BeaconRepository(remote, realtime.port);
      final repository = ForwardRepository(remote, beacons, realtime.port);
      addTearDown(() async {
        await repository.dispose();
        await beacons.dispose();
      });
      getIt
        ..registerSingleton<BeaconRepository>(beacons)
        ..registerSingleton<ForwardRepository>(repository)
        ..registerSingleton<ForwardCase>(
          ForwardCase(
            repository,
            auth,
            FakeBeaconViewFactCardRepository(),
            CountingProfileRepository(),
            contacts,
            noopBlockCase(),
          ),
        )
        ..registerSingleton<UiEffectPort>(FakeUiEffectPort());
      final router = _ForwardTestRouter(requestPage);
      getIt.registerSingleton<AppNavigator>(router);
      if (requestPage != null) {
        await registerBeaconViewHarnessGetIt(profile: _reader);
        await tester.binding.setSurfaceSize(kBeaconViewHarnessExpanded);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await getIt.reset();
      });
      if (locale.languageCode == 'ru') await usePhoneSurface(tester);
      await tester.pumpPeopleTagsWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ContextCubit>.value(value: _ForwardContext()),
            BlocProvider<ProfileCubit>.value(value: _ProfileCubit()),
          ],
          child: MaterialApp.router(
            routerConfig: router.config(
              deepLinkBuilder: (_) => DeepLink.path(
                requestPage == null ? _expectedForwardPath : _requestPath,
              ),
            ),
            locale: locale,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            builder: (_, child) => TenturaResponsiveScope(child: child!),
          ),
        ),
      );
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (verifyNavigation != null) {
        await verifyNavigation(router);
      } else {
        _expectForwardRoute(router);
      }
    },
  );
  expect(
    sent.where((call) => call.operationName == 'BeaconFetchById'),
    isNotEmpty,
  );
}

void _expectForwardRoute(RootRouter router) {
  expect(router.currentPath, _expectedForwardPath);
  expect(router.navigationHistory.urlState.url, _expectedForwardPath);
  expect(find.byType(ForwardBeaconScreen), findsOneWidget);
}

Future<void> _openForwardDeepLink(
  WidgetTester tester, {
  required Locale locale,
  required bool canForward,
  bool canReadInvolvement = true,
}) => _pumpForwardRoutes(
  tester,
  locale: locale,
  canForward: canForward,
  canReadInvolvement: canReadInvolvement,
);

Future<void> _expectRequestForwardMenu(
  WidgetTester tester, {
  required bool allowed,
}) async {
  final overflow = find.byKey(TestIds.key(TestIds.beaconOverflowMenu));
  expect(overflow.hitTestable(), findsOneWidget);
  await tester.tap(overflow);
  await tester.pumpAndSettle();
  expect(find.byType(PopupMenuItem<String>), findsWidgets);
  expect(
    find.byKey(TestIds.key(TestIds.beaconForward)),
    allowed ? findsOneWidget : findsNothing,
  );
}

void main() {
  group('Server Forward permission', () {
    for (final canReadInvolvement in [false, true]) {
      testWidgets(
        'an uninvited Post member can offer help without Forward '
        'when involvement is ${canReadInvolvement ? 'readable' : 'private'}',
        (tester) async {
          const locale = Locale('ru');
          final l10n = lookupL10n(locale);
          await _openRequestFromWire(
            tester,
            canForward: false,
            canReadInvolvement: canReadInvolvement,
            viewer: _reader,
            accessLevel: 2,
            accessReasons: 64,
            parentPostId: _postId,
            locale: locale,
          );
          expect(find.text(l10n.labelOfferHelp), findsOneWidget);
          expect(find.text(l10n.labelForward), findsNothing);
          expect(find.byTooltip(l10n.labelForward), findsNothing);
          expect(find.text(l10n.beaconHudYouForward), findsNothing);
          expect(find.text(l10n.beaconHudYouForwardAfterDecline), findsNothing);
          await _expectRequestForwardMenu(tester, allowed: false);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final (role, viewer, level, reasons, allowed) in [
      ('author', _author, 0, 1, false),
      ('admitted helper', _reader, 1, 4, false),
      ('uninvolved viewer', _reader, 2, 32, false),
      ('uninvolved viewer', _reader, 2, 32, true),
    ]) {
      testWidgets(
        'the Request shows ${allowed ? 'Forward' : 'no Forward'} to the $role '
        'when the server ${allowed ? 'allows' : 'denies'} it',
        (tester) async {
          const locale = Locale('en');
          final l10n = lookupL10n(locale);
          await _openRequestFromWire(
            tester,
            canForward: allowed,
            canReadInvolvement: true,
            viewer: viewer,
            accessLevel: level,
            accessReasons: reasons,
            locale: locale,
          );
          expect(
            find.text(l10n.labelForward),
            allowed ? findsOneWidget : findsNothing,
          );
          expect(find.byTooltip(l10n.labelForward), findsNothing);
          if (!allowed) {
            expect(find.text(l10n.beaconHudYouForward), findsNothing);
            expect(
              find.text(l10n.beaconHudYouForwardAfterDecline),
              findsNothing,
            );
          }
          await _expectRequestForwardMenu(tester, allowed: allowed);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'the Request page and menu open the Forward URL for that Request',
      (
        tester,
      ) async {
        const locale = Locale('en');
        final l10n = lookupL10n(locale);
        final cubit = await _loadRequestFromWire(
          tester,
          canForward: true,
          canReadInvolvement: true,
          viewer: _reader,
          accessLevel: 2,
          accessReasons: 64,
          parentPostId: _postId,
        );
        final host = beaconViewHarnessHost(beaconId: _requestId);
        addTearDown(() async {
          final closing = host.close();
          await tester.pump();
          await closing;
        });
        await _pumpForwardRoutes(
          tester,
          locale: locale,
          canForward: true,
          requestPage: buildBeaconViewHarnessWidget(
            beaconState: cubit.state,
            beaconViewCubit: cubit,
            threadsState: beaconViewHarnessThreadsState(authorId: _reader.id),
            host: host,
          ),
          verifyNavigation: (router) async {
            expect(router.currentPath, _requestPath);
            expect(find.text(_requestTitle), findsWidgets);
            expect(find.text(l10n.labelOfferHelp), findsOneWidget);
            final action = find.text(l10n.labelForward);
            expect(action, findsOneWidget);
            await tester.ensureVisible(action);
            await tester.tap(action);
            await tester.pumpAndSettle();
            _expectForwardRoute(router);
            expect(find.text(_recipientName), findsOneWidget);

            router.pop();
            await tester.pumpAndSettle();
            expect(router.currentPath, _requestPath);
            await _expectRequestForwardMenu(tester, allowed: true);
            await tester.tap(find.byKey(TestIds.key(TestIds.beaconForward)));
            await tester.pumpAndSettle();
            _expectForwardRoute(router);
            expect(find.text(_recipientName), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      },
    );

    testWidgets('a live Post respects permission on its page and info sheet', (
      tester,
    ) async {
      const locale = Locale('en');
      final l10n = lookupL10n(locale);
      for (final canForward in [false, true]) {
        await pumpLivePostForForwardPermission(
          tester,
          canForward: canForward,
          locale: locale,
        );
        final expected = canForward ? findsOneWidget : findsNothing;
        expect(find.byTooltip(l10n.labelForward), expected);
        await openPostInfoSheet(tester, l10n);
        expect(find.text(l10n.postInfoActionForward), expected);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });

    for (final (locale, denied) in [
      (const Locale('en'), _englishDenial),
      (const Locale('ru'), _russianDenial),
    ]) {
      testWidgets(
        'a denied Forward deep link explains the restriction in ${locale.languageCode}',
        (tester) async {
          await _openForwardDeepLink(
            tester,
            locale: locale,
            canForward: false,
            canReadInvolvement: false,
          );
          expect(tester.takeException(), isNull);
          final l10n = lookupL10n(locale);
          expect(find.byType(ForwardRecipientPicker), findsNothing);
          expect(find.textContaining(denied), findsOneWidget);
          expect(find.text(_recipientName), findsNothing);
          expect(find.byKey(TestIds.key(TestIds.forwardSubmit)), findsNothing);
          expect(find.text(l10n.forwardInviteNewPerson), findsNothing);
          expect(find.textContaining(_involvementDenial), findsNothing);
          expect(find.textContaining('Exception'), findsNothing);
          expect(
            find.textContaining('Forwarding is only available while'),
            findsNothing,
          );
          if (locale.languageCode == 'ru') {
            expect(find.textContaining(_englishDenial), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Forward is unavailable even with readable involvement', (
      tester,
    ) async {
      await _openForwardDeepLink(
        tester,
        locale: const Locale('en'),
        canForward: false,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ForwardRecipientPicker), findsNothing);
      expect(find.textContaining(_englishDenial), findsOneWidget);
      expect(find.text(_recipientName), findsNothing);
      expect(find.byKey(TestIds.key(TestIds.forwardSubmit)), findsNothing);
    });

    testWidgets(
      'an allowed Forward deep link lets the viewer select a recipient',
      (
        tester,
      ) async {
        const locale = Locale('en');
        final l10n = lookupL10n(locale);
        await _openForwardDeepLink(tester, locale: locale, canForward: true);
        expect(find.byType(ForwardRecipientPicker), findsOneWidget);
        final recipient = find.text(_recipientName);
        expect(recipient, findsOneWidget);
        await tester.tap(recipient);
        await tester.pumpAndSettle();
        final submit = find.byKey(TestIds.key(TestIds.forwardSubmit));
        expect(
          find.descendant(
            of: submit,
            matching: find.text(l10n.forwardToCount(1)),
          ),
          findsOneWidget,
        );
        expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNotNull);
        expect(find.textContaining(_englishDenial), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'the Forward denial has matching Request copy keys in English and Russian',
      () {
        Map<String, dynamic> arb(String locale) =>
            jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>;

        final en = arb('en');
        final ru = arb('ru');
        final commonKeys = en.keys.where((key) {
          final english = en[key];
          final russian = ru[key];
          return !key.startsWith('@') &&
              english is String &&
              russian is String &&
              _englishDenial.hasMatch(english) &&
              _russianDenial.hasMatch(russian);
        });
        expect(commonKeys, isNotEmpty);
        final key = commonKeys.first;
        expect(en[key], contains('Request'));
        final forbidden = RegExp('beacon|маяк', caseSensitive: false);
        expect(en[key], isNot(contains(forbidden)));
        expect(ru[key], isNot(contains(forbidden)));
      },
    );
  });
}
