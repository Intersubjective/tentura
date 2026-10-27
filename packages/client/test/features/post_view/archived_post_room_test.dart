// An archived Post (closed, or past its `expiresAt` while still open) is
// read-only but not dead: the room says so and offers «Оформить запрос» in
// place of the composer, ⋮ keeps «Оформить запрос» (plan D1), and leaving
// stays available (personal state, not content), with «Вернуть» bringing the
// member back. No composer, no reactions. Message menus keep only personal
// actions: delete own message, bud a Request from it.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/reaction_quick_picker.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/data/repository/post_membership_repository.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/message/post_messages.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/post_view/ui/widget/post_action.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/graph_trust_write_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostarchive1';
const _rootId = 'Mpostroot001';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');

final _createdAt = DateTime.utc(2026, 10, 24, 12);
final _now = DateTime.utc(2026, 10, 27, 12);

const _archivedHint =
    'Пост в архиве — писать нельзя. Продолжить разговор можно в запросе.';
const _budLabel = 'Оформить запрос';
const _leaveLabel = 'Выйти из чата';
const _leaveConfirm = 'Выйти';
const _deleteMessage = 'Удалить сообщение';
const _reply = 'Ответить';
const _editMessage = 'Изменить сообщение';

/// How the Post became archived.
enum _Archive { closed, expired }

Beacon _post(_Archive archive) => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  status: archive == _Archive.closed ? BeaconStatus.closed : BeaconStatus.open,
  expiresAt: archive == _Archive.closed
      ? null
      : _now.subtract(const Duration(hours: 1)),
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

final _messages = [
  _msg(_rootId, _author, 'Кто в субботу на велопрогулку?'),
  _msg('Mmine', _reader, 'Могу взять насос'),
];

RoomMessage _batonMsg(Profile author) => RoomMessage(
  id: 'Mbaton',
  beaconId: _postId,
  authorId: author.id,
  author: author,
  body: 'Кто довезёт насос в пятницу?',
  createdAt: _createdAt,
  semanticMarker: BeaconRoomSemanticMarker.baton,
  baton: const RoomBatonAuthorData(
    id: 'baton-1',
    status: RoomBatonStatus.collecting,
    candidates: [
      RoomBatonCandidate(
        userId: 'Uauthor',
        title: 'Олег',
        tier: 1,
        response: RoomBatonResponse.canHelp,
      ),
    ],
    allAnswered: true,
    eligibleCount: 1,
  ),
);

/// Records leave / return; nothing else is expected to be called.
class _Membership implements PostMembershipRepository {
  final left = <String>[];
  final returned = <String>[];

  @override
  Future<void> postLeave(String beaconId) async => left.add(beaconId);

  @override
  Future<void> postReturn(String beaconId) async => returned.add(beaconId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

class _IdleBlockCase extends Mock implements BlockCase {
  @override
  Stream<RepositoryEvent<BlockIntent>> get changes => const Stream.empty();
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
  required _Archive archive,
  Profile viewer = _reader,
  List<RoomMessage>? messages,
  _Membership? membership,
  FakeUiEffectPort? effects,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = _ProfileCubit(viewer);
  // The participants list in «О посте» builds profile cubits from DI.
  final profiles = GraphTrustWriteFixture();
  addTearDown(profiles.dispose);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ProfileViewCase>(profiles.profileViewCase)
    ..registerSingleton<BlockCase>(_IdleBlockCase())
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_ForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(_PostsRepository());

  final screenEffects = effects ?? FakeUiEffectPort();
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: viewer,
    beaconRepository: _PostRepository(_post(archive)),
    effects: screenEffects,
    membershipRepository: membership,
    clock: () => _now,
  );
  addTearDown(cubit.close);
  await cubit.fetch();

  final room = _RoomCubit(
    roomBodyState(
      beaconId: _postId,
      myUserId: viewer.id,
      messages: messages ?? _messages,
      // The room's own view of the lifecycle: a closed Post is locked.
      beaconStatus: archive == _Archive.closed
          ? BeaconStatus.closed
          : BeaconStatus.open,
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
                  create: (_) => ScreenCubit(screenEffects),
                ),
              ],
              // Budding is on by default (kPostBuddingEnabled).
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

Future<void> _closeMenu(WidgetTester tester) async {
  await tester.tapAt(Offset.zero);
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
}

/// Opens the actions of a message by its body text with a secondary click.
Future<void> _openActionsOf(WidgetTester tester, String body) async {
  await tester.tapAt(
    tester.getTopLeft(find.textContaining(body).last) + const Offset(8, 8),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await _settle(tester);
}

Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

final _budMessageAction = find.byKey(const Key('Room.BudRequestAction'));

Finder _inRoom(Finder finder) =>
    find.descendant(of: find.byType(BeaconRoomBody), matching: finder);

/// A text field in the room a member could type into.
final _enabledComposer = _inRoom(
  find.byWidgetPredicate((w) => w is TextField && w.enabled != false),
);

void main() {
  group('archived Post room', () {
    for (final archive in _Archive.values) {
      testWidgets('${archive.name}: shows the archive hint and «Оформить '
          'запрос» instead of the composer', (tester) async {
        await _pump(tester, archive: archive);

        expect(_inRoom(find.text(_archivedHint)), findsOneWidget);
        expect(_inRoom(find.text(_budLabel)), findsOneWidget);
        expect(_enabledComposer, findsNothing);
        // The old generic read-only line is replaced.
        expect(find.text('Этот чат доступен только для чтения'), findsNothing);
      });

      testWidgets('${archive.name}: no reactions on messages', (tester) async {
        await _pump(tester, archive: archive);

        await _openMessageActions(tester);
        expect(find.byType(ReactionQuickPicker), findsNothing);
      });

      testWidgets('${archive.name}: the room «Оформить запрос» opens the same '
          'form as ⋮', (tester) async {
        final router = await _pump(tester, archive: archive);
        router.pushed.clear();

        await tester.tap(_inRoom(find.text(_budLabel)));
        await _settle(tester);

        final args = router.pushed.single.args! as BeaconCreateRouteArgs;
        expect(args.parentBeaconId, _postId);
        // A member who is not the author starts blank, as from ⋮.
        expect(args.sourceMessageId, '');
      });
    }
  });

  group('archived Post ⋮', () {
    for (final archive in _Archive.values) {
      testWidgets('${archive.name}: «Оформить запрос» is offered', (
        tester,
      ) async {
        final router = await _pump(tester, archive: archive);
        router.pushed.clear();

        await _openOverflow(tester);
        // The room offers its own «Оформить запрос»; this is the ⋮ entry.
        final menuEntry = find.descendant(
          of: find.byType(PopupMenuItem<PostAction>),
          matching: find.text(_budLabel),
        );
        expect(menuEntry, findsOneWidget);
        await tester.tap(menuEntry);
        await _settle(tester);

        final args = router.pushed.single.args! as BeaconCreateRouteArgs;
        expect(args.parentBeaconId, _postId);
      });

      testWidgets('${archive.name}: a member can still leave', (tester) async {
        await _pump(tester, archive: archive);

        await _openOverflow(tester);
        expect(find.text(_leaveLabel), findsOneWidget);
        await _closeMenu(tester);
      });

      testWidgets('${archive.name}: «О посте» still offers leaving', (
        tester,
      ) async {
        await _pump(tester, archive: archive);

        await _openOverflow(tester);
        await tester.tap(find.text('О посте'));
        await _settle(tester);
        expect(find.text(_leaveLabel), findsOneWidget);
      });
    }
  });
  group('archived Post room message actions', () {
    for (final archive in _Archive.values) {
      testWidgets('${archive.name}: own message offers delete and bud only', (
        tester,
      ) async {
        await _pump(tester, archive: archive);

        await _openActionsOf(tester, 'Могу взять насос');
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(_inSheet(_deleteMessage), findsOneWidget);
        expect(_budMessageAction, findsOneWidget);
        expect(_inSheet(_reply), findsNothing);
        expect(_inSheet(_editMessage), findsNothing);
        expect(find.byType(ReactionQuickPicker), findsNothing);
      });

      testWidgets("${archive.name}: another member's message offers neither "
          'delete nor bud', (tester) async {
        await _pump(tester, archive: archive);

        await _openActionsOf(tester, 'Кто в субботу на велопрогулку?');
        expect(_inSheet(_deleteMessage), findsNothing);
        expect(_budMessageAction, findsNothing);
        expect(_inSheet(_reply), findsNothing);
        expect(_inSheet(_editMessage), findsNothing);
        expect(find.byType(ReactionQuickPicker), findsNothing);
      });

      testWidgets('${archive.name}: own baton message offers delete only', (
        tester,
      ) async {
        await _pump(
          tester,
          archive: archive,
          messages: [..._messages, _batonMsg(_reader)],
        );

        await tester.longPressAt(
          tester.getTopLeft(find.byType(RoomBatonCard)) + const Offset(8, 8),
        );
        await _settle(tester);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(_inSheet(_deleteMessage), findsOneWidget);
        for (final text in [
          'Изменить',
          _reply,
          'Отменить',
          _budLabel,
        ]) {
          expect(_inSheet(text), findsNothing, reason: text);
        }
      });
    }
  });

  group('archived Post: leave and «Вернуть»', () {
    for (final archive in _Archive.values) {
      testWidgets('${archive.name}: a member leaves and «Вернуть» brings '
          'them back', (tester) async {
        final membership = _Membership();
        final effects = FakeUiEffectPort();
        await _pump(
          tester,
          archive: archive,
          membership: membership,
          effects: effects,
        );

        await _openOverflow(tester);
        await tester.tap(find.text(_leaveLabel));
        await _settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(_leaveConfirm),
          ),
        );
        await _settle(tester);
        expect(membership.left, [_postId]);

        final left = effects.emitted
            .whereType<ShowMessage>()
            .map((e) => e.message)
            .whereType<PostLeftMessage>()
            .single;
        expect(left.label.toRu, 'Вернуть');
        left.onPressed();
        await _settle(tester);

        expect(membership.returned, [_postId]);
        expect(
          effects.emitted.whereType<NavigatePush>().map((e) => e.path),
          contains('$kPathBeaconView/$_postId'),
        );
      });
    }
  });
}
