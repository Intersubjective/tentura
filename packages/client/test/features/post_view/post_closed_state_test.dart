// A Post closed by budding is read-only (plan D2): the kind-5 notice, a
// disabled composer, and no reactions, forward or leave. An open Post keeps
// them (the control case).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:tentura/features/beacon_threads/ui/widget/reaction_quick_picker.dart';
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
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostclosed01';
const _rootId = 'Mpostroot001';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');

final _createdAt = DateTime.utc(2026, 10, 2, 12);

Beacon _post({BeaconStatus status = BeaconStatus.open}) => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  status: status,
  author: _author,
  postRootMessageId: _rootId,
  viewerCanForward: true,
);

RoomMessage _msg(String id, Profile author, String body) => RoomMessage(
  id: id,
  beaconId: _postId,
  authorId: author.id,
  author: author,
  body: body,
  createdAt: _createdAt,
);

final _closedNotice = RoomMessage(
  id: 'Mclosed',
  beaconId: _postId,
  authorId: '',
  body: '',
  createdAt: _createdAt,
  systemMessageKind: BeaconRoomSystemMessageKind.postClosed,
  systemPayloadJson: jsonEncode({
    'childBeaconId': 'Bchild01',
    'title': 'Велопрогулка в субботу',
  }),
);

List<RoomMessage> _messages(BeaconStatus status) => [
  _msg(_rootId, _author, 'Кто в субботу на велопрогулку?'),
  _msg('Mmine', _reader, 'Могу взять насос'),
  if (status == BeaconStatus.closed) _closedNotice,
];

class _PostRepository implements BeaconRepository {
  _PostRepository(this.beacon);

  final Beacon beacon;

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ForwardRepository implements ForwardRepository {
  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PostsRepository implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => const [];

  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

class _ProfileCubit extends Mock implements ProfileCubit {
  _ProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _ThreadsCubit extends Mock implements ThreadsCubit {
  _ThreadsCubit(this._state);

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

class _Router extends BeaconViewHarnessRouter {
  final pushed = <PageRouteInfo>[];

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    pushed.add(route);
    return super.push(route, onFailure: onFailure);
  }
}

Future<_Router> _pump(
  WidgetTester tester, {
  required Profile viewer,
  required BeaconStatus status,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = _ProfileCubit(viewer);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_ForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(_PostsRepository());

  final effects = FakeUiEffectPort();
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: viewer,
    beaconRepository: _PostRepository(_post(status: status)),
    effects: effects,
  );
  addTearDown(cubit.close);
  await cubit.fetch();

  final room = _RoomCubit(
    roomBodyState(
      beaconId: _postId,
      myUserId: viewer.id,
      messages: _messages(status),
      beaconStatus: status,
    ).copyWith(
      participants: [
        roomBodyAdmittedParticipant(
          beaconId: _postId,
          profile: viewer,
          role: viewer.id == _author.id
              ? BeaconParticipantRoleBits.author
              : BeaconParticipantRoleBits.addressee,
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
          required beaconId,
          threadItemId,
          initialUnreadAnchorAt,
          capabilities = const RoomCapabilities.request(),
        }) => room,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final closing = threadHost.close();
    await tester.pump();
    await closing;
  });

  final router = _Router();
  const surface = Size(700, 900);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
          data: const MediaQueryData(size: surface),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PostViewCubit>.value(value: cubit),
                BlocProvider<ThreadsCubit>.value(
                  value: _ThreadsCubit(
                    ThreadsState(
                      threads: [
                        RequestThread(
                          threadId: RequestThread.generalId,
                          kind: RequestThreadKind.general,
                          lastSeenAt: _createdAt,
                        ),
                      ],
                      myUserId: viewer.id,
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
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openOverflow(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.more_vert),
    ),
  );
  await _settle(tester);
}

/// Opens the actions of the author's root message with a secondary click.
Future<void> _openMessageActions(WidgetTester tester) async {
  final body = find.textContaining('Кто в субботу на велопрогулку?');
  await tester.tapAt(
    tester.getTopLeft(body.last) + const Offset(8, 8),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await _settle(tester);
  expect(find.byType(BottomSheet), findsOneWidget);
}

final _forwardButton = find.descendant(
  of: find.byType(AppBar),
  matching: find.byIcon(Icons.north_east),
);

void main() {
  testWidgets('open Post: forward, leave, reactions and the composer', (
    tester,
  ) async {
    await _pump(tester, viewer: _reader, status: BeaconStatus.open);

    expect(_forwardButton, findsOneWidget);
    expect(
      find.text('Этот чат доступен только для чтения'),
      findsNothing,
    );
    await _openOverflow(tester);
    expect(find.text('Выйти из чата'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await _settle(tester);

    await _openMessageActions(tester);
    expect(find.byType(ReactionQuickPicker), findsOneWidget);
  });

  testWidgets('closed Post: notice, disabled composer, no write actions', (
    tester,
  ) async {
    await _pump(tester, viewer: _reader, status: BeaconStatus.closed);

    expect(
      find.text(
        'Пост закрыт. Разговор продолжается в запросе «Велопрогулка в субботу».',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Этот чат доступен только для чтения'),
      findsOneWidget,
    );
    expect(_forwardButton, findsNothing);

    await _openOverflow(tester);
    expect(find.text('Выйти из чата'), findsNothing);
    await tester.tapAt(Offset.zero);
    await _settle(tester);

    await _openMessageActions(tester);
    expect(find.byType(ReactionQuickPicker), findsNothing);
  });
}
