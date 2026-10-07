import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_create/post_conversion_helper_handoff_test.dart'
    as conversion;
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostconvert1';
const _rootId = 'Mpostroot001';
const _rootText = 'Кто в субботу на велопрогулку?';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');
const _secondMember = Profile(id: 'Usecond', displayName: 'Анна');
const _unselectedMember = Profile(id: 'Uthird', displayName: 'Иван');

final _createdAt = DateTime.utc(2026, 10, 2, 12);

Beacon _post() => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  status: BeaconStatus.open,
  canReadContent: true,
  author: _author,
  postRootMessageId: _rootId,
);

RoomMessage _rootMessage() => RoomMessage(
  id: _rootId,
  beaconId: _postId,
  authorId: _author.id,
  author: _author,
  body: _rootText,
  createdAt: _createdAt,
);

class _PostRepository implements BeaconRepository {
  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => _post();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeForwardRepository implements ForwardRepository {
  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostsRepository implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => [
    PostSummary(
      id: _postId,
      authorId: _author.id,
      authorName: _author.displayName,
      rootExcerpt: _rootText,
      lastActivityAt: _createdAt,
    ),
  ];

  @override
  Future<PostSummary?> postSummary(String id) async =>
      (await myPosts()).where((p) => p.id == id).firstOrNull;
}

class _ProfileCubit extends Mock implements ProfileCubit {
  _ProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  _MockThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream.value(_state);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

class _RoomCubit extends RoomBodyHarnessCubit {
  _RoomCubit(super.initial);

  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async => _closed = true;

  @override
  Future<void> load() async {}

  @override
  void prepareThreadScroll({String? messageId, String? coordinationItemId}) {}
}

/// Keeps every route the screen pushes, so a test can read its arguments.
class _RecordingRouter extends BeaconViewHarnessRouter {
  final pushed = <PageRouteInfo>[];

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushed.add(route);
    return null;
  }
}

Future<_RecordingRouter> _pumpPost(
  WidgetTester tester, {
  required Profile viewer,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = _ProfileCubit(viewer);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_FakeForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(_FakePostsRepository());

  final effects = FakeUiEffectPort();
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: viewer,
    beaconRepository: _PostRepository(),
    effects: effects,
  );
  addTearDown(cubit.close);
  await cubit.fetch();

  final room = _RoomCubit(
    roomBodyState(
      beaconId: _postId,
      myUserId: viewer.id,
      messages: [_rootMessage()],
    ).copyWith(
      participants: [
        roomBodyAdmittedParticipant(
          beaconId: _postId,
          profile: _author,
          role: BeaconParticipantRoleBits.author,
        ),
        for (final member in [_reader, _secondMember, _unselectedMember])
          roomBodyAdmittedParticipant(
            beaconId: _postId,
            profile: member,
            role: BeaconParticipantRoleBits.addressee,
          ),
      ],
      participantsLoaded: true,
    ),
  );
  final threadHost = ThreadHostCubit(
    beaconId: _postId,
    capabilities: const RoomCapabilities.post(),
    roomCubitFactory:
        ({
          required String beaconId,
          String? threadItemId,
          DateTime? initialUnreadAnchorAt,
          RoomCapabilities capabilities = const RoomCapabilities.request(),
        }) => room,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // close() needs the fake-async microtask queue pumped to complete;
    // awaiting it bare hangs (it used to be masked by a 5 s timeout per test).
    final closing = threadHost.close();
    await tester.pump();
    await closing;
  });

  final general = RequestThread(
    threadId: RequestThread.generalId,
    kind: RequestThreadKind.general,
    lastSeenAt: _createdAt,
  );

  await tester.binding.setSurfaceSize(const Size(700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _RecordingRouter();
  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(700, 900)),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PostViewCubit>.value(value: cubit),
                BlocProvider<ThreadsCubit>.value(
                  value: _MockThreadsCubit(
                    ThreadsState(
                      threads: [general],
                      myUserId: viewer.id,
                      status: const StateIsSuccess(),
                    ),
                  ),
                ),
                BlocProvider<ThreadHostCubit>.value(value: threadHost),
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<PresenceCubit>.value(
                  value: RoomBodyHarnessPresenceCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(effects),
                ),
              ],
              child: const PostViewScreen(id: _postId),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(BeaconRoomBody).evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byType(BeaconRoomBody), findsOneWidget);
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openOverflow(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byType(AppBar),
    matching: find.byIcon(Icons.more_vert),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await _settle(tester);
}

const _menuLabel = 'Превратить в запрос';

/// ⋮ → «О посте»: the sheet that holds the convert item.
Future<void> _openInfo(WidgetTester tester) async {
  await _openOverflow(tester);
  await tester.tap(find.text('О посте'));
  await _settle(tester);
}

Future<void> _openConvertDialog(WidgetTester tester) async {
  await _openInfo(tester);
  await tester.ensureVisible(find.text(_menuLabel));
  await tester.tap(find.text(_menuLabel));
  await _settle(tester);
}

Finder _dialog() => find.byType(AlertDialog);

Finder _inDialog(Finder f) => find.descendant(of: _dialog(), matching: f);

Finder _memberRow(Profile member) => _inDialog(
  find.ancestor(
    of: find.text(member.shownName),
    matching: find.byType(CheckboxListTile),
  ),
);

Future<void> _selectMember(WidgetTester tester, Profile member) async {
  final row = _memberRow(member);
  expect(row, findsOneWidget, reason: 'Each post member needs a checkbox row');
  await tester.ensureVisible(row);
  // A regular tap on the label must work on desktop, web, and mobile.
  await tester.tap(
    find.descendant(of: row, matching: find.text(member.shownName)),
  );
  await tester.pump();
}

Future<BeaconCreateRoute> _confirm(
  WidgetTester tester,
  _RecordingRouter router,
) async {
  await tester.tap(_inDialog(find.textContaining('Далее')));
  await _settle(tester);
  expect(router.pushed, hasLength(1));
  return router.pushed.single as BeaconCreateRoute;
}

// Dynamic access keeps these tests runnable before the new route field exists.
// Once implemented, this reads the actual generated route arguments.
List<String> _helperIds(BeaconCreateRoute route) {
  final dynamic args = route.args!;
  try {
    final Object? ids = args.convertHelperIds;
    expect(ids, isA<Iterable<String>>());
    return (ids! as Iterable<String>).toList();
  } on NoSuchMethodError {
    fail('BeaconCreateRoute must carry convertHelperIds from the confirmation');
  }
}

void main() {
  group('Post conversion member selection', () {
    testWidgets(
      'confirming selected members builds the generated Request page and submits their ids through its cubit',
      (tester) async {
        final router = await _pumpPost(tester, viewer: _author);
        await _openConvertDialog(tester);
        await _selectMember(tester, _reader);
        await _selectMember(tester, _secondMember);
        final route = await _confirm(tester, router);
        final opened = await conversion.pumpConversionRoute(tester, route);
        expect(opened.fetchedIds, [_postId]);
        expect(opened.convertedIds, isEmpty);
        expect(await opened.cubit.submitConversion(), _postId);
        expect(opened.convertedIds, [_postId]);
        expect(opened.convertedHelpers, [
          unorderedEquals([_reader.id, _secondMember.id]),
        ]);
      },
    );

    testWidgets('shows the localized member carry-over explanation', (
      tester,
    ) async {
      await _pumpPost(tester, viewer: _author);
      await _openConvertDialog(tester);
      final dynamic l10n = L10n.of(tester.element(_dialog()))!;
      String explanation;
      try {
        explanation = l10n.postConvertMembersExplanation as String;
      } on NoSuchMethodError {
        fail('The member picker needs a localized carry-over explanation');
      }
      expect(explanation.trim(), isNotEmpty);
      expect(_inDialog(find.text(explanation)), findsOneWidget);
    });

    testWidgets('lists every non-author member with an unchecked checkbox', (
      tester,
    ) async {
      await _pumpPost(tester, viewer: _author);
      await _openConvertDialog(tester);
      for (final member in [_reader, _secondMember, _unselectedMember]) {
        final row = _memberRow(member);
        expect(
          row,
          findsOneWidget,
          reason: '${member.shownName} must be selectable',
        );
        expect(tester.widget<CheckboxListTile>(row).value, isFalse);
      }
      expect(_memberRow(_author), findsNothing);
      expect(_inDialog(find.text(_author.shownName)), findsNothing);
      // Three member checkboxes plus the existing discoverability checkbox.
      expect(_inDialog(find.byType(Checkbox)), findsNWidgets(4));
    });

    testWidgets(
      'confirming two checked members carries exactly their ids to the Request form',
      (tester) async {
        final router = await _pumpPost(tester, viewer: _author);
        await _openConvertDialog(tester);
        await _selectMember(tester, _reader);
        await _selectMember(tester, _secondMember);
        final route = await _confirm(tester, router);
        expect(route.args!.convertFromPostId, _postId);
        expect(
          _helperIds(route),
          unorderedEquals([_reader.id, _secondMember.id]),
        );
        expect(route.args!.convertIsDiscoverable, isTrue);
      },
    );

    testWidgets(
      'confirming without checking members submits an explicit empty helper list through generated navigation',
      (tester) async {
        final router = await _pumpPost(tester, viewer: _author);
        await _openConvertDialog(tester);
        final route = await _confirm(tester, router);
        expect(_helperIds(route), isEmpty);
        final opened = await conversion.pumpConversionRoute(tester, route);
        expect(opened.fetchedIds, [_postId]);
        expect(opened.convertedIds, isEmpty);
        expect(await opened.cubit.submitConversion(), _postId);
        expect(opened.convertedIds, [_postId]);
        expect(opened.convertedHelpers, [<String>[]]);
      },
    );

    testWidgets('unchecking a member removes their id before confirmation', (
      tester,
    ) async {
      final router = await _pumpPost(tester, viewer: _author);
      await _openConvertDialog(tester);
      await _selectMember(tester, _reader);
      await _selectMember(tester, _secondMember);
      await _selectMember(tester, _reader);
      final route = await _confirm(tester, router);
      expect(_helperIds(route), [_secondMember.id]);
    });
  });
}
