// Opening «Новый пост» from a profile (`/post/new?forward_to=<user id>`)
// pre-selects that user as the recipient on the screen's shared ForwardCubit:
// the «Кому» row names them and ➤ publishes to them without any picking.
// The route wrapper (`PostCreateScreen.wrappedRoute`) builds the cubits from
// GetIt, so this runs the real ForwardCubit over a fake ForwardCase.

import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/port/post_publish_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import 'fake_beacon_ports.dart';

const _target = Profile(
  id: 'U-target',
  displayName: 'Target',
  score: 1,
  rScore: 1,
);

class _ForwardRepository implements ForwardRepository {
  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => const [_target];

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon.empty.copyWith(
      id: beaconId,
      author: const Profile(id: 'U-me'),
    ),
    forwardedToIds: <String>{},
    helpOfferedIds: <String>{},
    withdrawnIds: <String>{},
    rejectedIds: <String>{},
    watchingIds: <String>{},
    onwardForwarderIds: <String>{},
    myForwardedRecipientNotes: <String, String>{},
    myForwardedRecipientEdgeIds: <String, String>{},
    myForwardedRecipientReadAts: <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: <String, bool>{},
    myForwardedRecipientRejected: <String, bool>{},
  );

  @override
  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) async => const LineageForwardSuggestions(
    sourceBeaconId: '',
    rootBeaconId: '',
    suggestedNote: '',
    suggestions: [],
  );

  @override
  Future<void> dispose() => _forwardChanges.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileRepository implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (id == _target.id) _target,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'U-me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _Router extends Mock implements StackRouter {}

class _RecordingPostPublishPort implements PostPublishPort {
  final recipients = <Set<String>>[];

  @override
  Future<PostPublishResult> postPublish({
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    RoomPendingUpload? attachment,
  }) async {
    recipients.add(recipientIds.toSet());
    return PostPublishResult(beaconId: beaconId, rootMessageId: 'root-1');
  }

  @override
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {}
}

/// Registers the collaborators the Post create route builds its cubits from.
Future<_RecordingPostPublishPort> _setUpCollaborators(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);

  final authLocal = StreamingAuthLocal('U-me');
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  getIt.registerSingleton<ContactNameStore>(store);
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  contactsRepo.fetchMineHandler = () async => {};
  final synced = contactsRepo.nextSync();
  authLocal.emit('U-me');
  await synced;
  final forwardRepo = _ForwardRepository();
  addTearDown(() async {
    await forwardRepo.dispose();
    await contactsCase.dispose();
    await store.dispose();
  });

  final effects = FakeUiEffectPort();
  final port = _RecordingPostPublishPort();
  getIt
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ProfileCubit>(_ProfileCubit())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<BeaconCreateCase>(fakeBeaconCreateCase())
    ..registerSingleton<PostPublishCase>(PostPublishCase(port))
    ..registerSingleton<ForwardCase>(
      ForwardCase(
        forwardRepo,
        authLocal,
        _FactCardRepository(),
        _ProfileRepository(),
        contactsCase,
        noopBlockCase(),
        env: const Env(),
        logger: Logger('test'),
      ),
    );

  return port;
}

Future<_RecordingPostPublishPort> _pumpScreen(
  WidgetTester tester, {
  required String forwardToUserId,
}) async {
  final port = await _setUpCollaborators(tester);
  final getIt = GetIt.I;
  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: getIt<ProfileCubit>()),
                BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit.local(),
                ),
              ],
              child: Builder(
                builder: (context) => PostCreateScreen(
                  forwardToUserId: forwardToUserId,
                ).wrappedRoute(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return port;
}

/// Minimal router mounting the production page at the production path.
class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: PostCreateRoute.page, path: kPathPostNew),
  ];
}

/// Opens [uri] through the router like a deep link or a pushed path.
Future<_RecordingPostPublishPort> _pumpDeepLink(
  WidgetTester tester,
  String uri,
) async {
  final port = await _setUpCollaborators(tester);
  final getIt = GetIt.I;
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: getIt<ProfileCubit>()),
        BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        routerConfig: _TestRouter().config(
          deepLinkBuilder: (_) => DeepLink.path(uri),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return port;
}

Finder get _composerField => find.descendant(
  of: find.byType(BeaconRoomComposer),
  matching: find.byType(TextField),
);

Finder get _sendButton => find.byKey(TestIds.key(TestIds.roomMessageSend));

bool _sendEnabled(WidgetTester tester) =>
    tester.widget<IconButton>(_sendButton).onPressed != null;

void main() {
  group('opening «Новый пост» for a specific user', () {
    testWidgets('names that user in the «Кому» row', (tester) async {
      await _pumpScreen(tester, forwardToUserId: 'U-target');

      expect(find.textContaining('Target'), findsWidgets);
    });

    testWidgets('lets ➤ publish to that user without picking anyone', (
      tester,
    ) async {
      final port = await _pumpScreen(tester, forwardToUserId: 'U-target');

      await tester.enterText(_composerField, 'Привет!');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_sendEnabled(tester), isTrue);

      await tester.tap(_sendButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(port.recipients, [
        {'U-target'},
      ]);
    });

    testWidgets(
      'without a forward-to user nobody is pre-selected, but ➤ still '
      'publishes to no one',
      (tester) async {
        final port = await _pumpScreen(tester, forwardToUserId: '');

        await tester.enterText(_composerField, 'Привет!');
        await tester.pump(const Duration(milliseconds: 100));

        expect(_sendEnabled(tester), isTrue);
        await tester.tap(_sendButton);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(port.recipients, [<String>{}]);
      },
    );
  });

  group('deep link /post/new', () {
    // The user id is carried under the repo's `forward_to` query key (like the
    // Request form) and, spelled out, as `forwardToUserId`; both keys carry the
    // same id so the test does not depend on which one the route declares.
    final query = '$kQueryBeaconForwardTo=U-target&forwardToUserId=U-target';

    testWidgets('opens the Post create screen with the user pre-selected', (
      tester,
    ) async {
      final port = await _pumpDeepLink(tester, '$kPathPostNew?$query');

      expect(find.byType(PostCreateScreen), findsOneWidget);
      expect(find.textContaining('Target'), findsWidgets);

      await tester.enterText(_composerField, 'Привет!');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_sendButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(port.recipients, [
        {'U-target'},
      ]);
    });

    testWidgets(
      'without a query opens an empty recipient list, but ➤ still publishes '
      'to no one',
      (tester) async {
        final port = await _pumpDeepLink(tester, kPathPostNew);

        expect(find.byType(PostCreateScreen), findsOneWidget);
        await tester.enterText(_composerField, 'Привет!');
        await tester.pump(const Duration(milliseconds: 100));
        expect(_sendEnabled(tester), isTrue);
        await tester.tap(_sendButton);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(port.recipients, [<String>{}]);
      },
    );

    test('is registered in the app router at kPathPostNew', () {
      final source = File('lib/app/router/root_router.dart').readAsStringSync();

      expect(
        source,
        matches(
          RegExp(r'page:\s*PostCreateRoute\.page,\s*path:\s*kPathPostNew'),
        ),
      );
    });
  });
}
