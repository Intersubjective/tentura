// A Post's Chat carries no facts strip or fact list (plan D17, R6, §6.6): the
// Post's facts live only in the info sheet. With two facts on the Post the
// mounted PostViewScreen shows the messages and no fact row, no «Facts»
// heading, and no facts-strip widget; the facts appear once the info sheet
// is opened.
//
// Mounted the production way (PostViewScreen over a ThreadHostCubit with
// Post capabilities and a real RoomCubit); the facts arrive over the real
// fact-card transport (HTTP -> Ferry -> BeaconFactCardRepository).

import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/graph_trust_write_fixture.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit;
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostfacts01';
const _rootId = 'Mpostroot001';
const _mineId = 'Mmine0000001';
const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Maria');

const _rootBody = 'Who has a ladder for Saturday?';
const _mineBody = 'The key is under the mat by the red door';

// The strings the person reads.

final _createdAt = DateTime.utc(2026, 11, 13, 12);
final _now = DateTime.utc(2026, 11, 14, 12);

Beacon _post({bool closed = false}) => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  status: closed ? BeaconStatus.closed : BeaconStatus.open,
  expiresAt: _now.add(const Duration(hours: 20)),
  author: _viewer,
  postRootMessageId: _rootId,
  viewerCanForward: true,
);

RoomMessage _msg(String id, String body, {String? linkedFactCardId}) =>
    RoomMessage(
      id: id,
      beaconId: _postId,
      authorId: _viewer.id,
      author: _viewer,
      body: body,
      createdAt: _createdAt,
      linkedFactCardId: linkedFactCardId,
    );

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

/// A real RoomCubit for [beaconId] over the real BeaconThreadsCase.
RoomCubit _realRoomCubit({
  required String beaconId,
  required List<RoomMessage> messages,
  required BeaconFactCardRepository facts,
  required RoomCapabilities capabilities,
}) {
  final room = FakeBeaconThreadsRepository(userId: _viewer.id)
    ..messages = messages;
  addTearDown(room.dispose);
  final realtime = buildTestRealtimeSync();
  final roomCase = BeaconThreadsCase(
    room,
    facts,
    FakePollingRepository(),
    FakeBeaconRoomHintsRepository(),
    RoomReadWatermarkStore.testing(),
    realtime.case_,
  );
  return RoomCubit(
    beaconId: beaconId,
    beaconRoomCase: roomCase,
    coordinationItemRoomSync: CoordinationItemRoomSync(),
    presenceRepository: roomCubitFakePresenceRepository(),
    effects: FakeUiEffectPort(),
    capabilities: capabilities,
  );
}

/// Bounded pumps that let the real cubit's futures land.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// PostViewScreen for an open Post the viewer wrote, whose room is a real
/// RoomCubit with Post capabilities over [facts].
Future<RoomCubit> _pumpPost(
  WidgetTester tester, {
  required BeaconFactCardRepository facts,
  List<RoomMessage>? messages,
  Locale locale = const Locale('en'),
  Size size = const Size(700, 900),
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = _ProfileCubit(_viewer);
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
  registerFakeAppNavigator();

  final screenEffects = FakeUiEffectPort();
  final postCubit = PostViewCubit(
    id: _postId,
    myProfile: _viewer,
    beaconRepository: _PostRepository(_post()),
    effects: screenEffects,
    clock: () => _now,
  );
  addTearDown(postCubit.close);
  await tester.runAsync(postCubit.fetch);

  final room = _realRoomCubit(
    beaconId: _postId,
    messages: messages ?? [_msg(_rootId, _rootBody), _msg(_mineId, _mineBody)],
    facts: facts,
    capabilities: const RoomCapabilities.post(),
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
  )..syncBeaconStatus(BeaconStatus.open, authorId: _viewer.id);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final closing = threadHost.close();
    await tester.pump();
    await closing;
  });

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: BeaconViewHarnessRouter(),
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PostViewCubit>.value(value: postCubit),
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
                      myUserId: _viewer.id,
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
  threadHost.syncBeaconStatus(BeaconStatus.open, authorId: _viewer.id);
  await _settle(tester);
  expect(find.byType(BeaconRoomBody), findsOneWidget);
  return room;
}

class _ProfileCubit extends Mock implements ProfileCubit {
  _ProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

const _keyFact = 'Spare key under the third flowerpot';
const _glovesFact = 'Bring two pairs of work gloves';

/// The production fact-card repository over a faked transport that answers
/// BeaconFactCardList with [texts] as the Post's facts.
Future<BeaconFactCardRepository> _factsOverWire(
  WidgetTester tester,
  List<String> texts,
) async {
  late RemoteApiService remote;
  late BeaconFactCardRepository repository;
  await tester.runAsync(() async {
    await http.runWithClient(
      () async {
        remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        await remote.setSessionAuth();
        await remote.getAuthToken();
        repository = BeaconFactCardRepository(remote);
      },
      () => MockClient((request) async {
        http.Response json(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path.endsWith('/session/access-token')) {
          return json({
            'subject': _viewer.id,
            'access_token': 'test-token',
            'expires_in': 3600,
          });
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return json({
          'data': switch (body['operationName']) {
            'BeaconFactCardList' => {
              '__typename': 'query_root',
              'BeaconFactCardList': [
                for (var i = 0; i < texts.length; i++)
                  {
                    '__typename': 'v2_BeaconFactCardRow',
                    'id': 'Ffact000000${i + 1}',
                    'beaconId': _postId,
                    'factText': texts[i],
                    'visibility': BeaconFactCardVisibilityBits.room,
                    'pinnedBy': _viewer.id,
                    'pinnedByTitle': _viewer.displayName,
                    'sourceMessageId': null,
                    'status': BeaconFactCardStatusBits.active,
                    'createdAt': '2026-11-14T12:00:00.000Z',
                    'updatedAt': null,
                    'attachmentsJson': '[]',
                    'revisionSeq': 1,
                    'lastEditedBy': null,
                    'lastEditedByTitle': null,
                    'lastEditedAt': null,
                    'otherEditorCount': 0,
                    'historyTruncated': false,
                    'savedByMe': false,
                    'originBeaconKind': null,
                  },
              ],
            },
            _ => null,
          },
        });
      }),
    );
  });
  addTearDown(() => tester.runAsync(remote.close));
  return repository;
}

Finder _inRoom(Finder finder) =>
    find.descendant(of: find.byType(BeaconRoomBody), matching: finder);

void main() {
  group('Post Chat with facts', () {
    testWidgets('shows the messages and no facts strip or fact list; the '
        'facts are listed only in the info sheet', (tester) async {
      final facts = await _factsOverWire(tester, [_keyFact, _glovesFact]);
      final room = await _pumpPost(tester, facts: facts);
      expect(
        room.state.factCards.map((f) => f.factText),
        [_keyFact, _glovesFact],
        reason: 'the Post room holds both facts',
      );

      expect(
        _inRoom(find.textContaining(_mineBody, findRichText: true)),
        findsWidgets,
        reason: 'the Chat shows its messages',
      );
      expect(find.byType(BeaconPinnedFactCard), findsNothing);
      expect(find.text(_keyFact), findsNothing);
      expect(find.text(_glovesFact), findsNothing);
      expect(find.text('Facts'), findsNothing);

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text(l10n.postMenuInfo));
      await _settle(tester);

      expect(find.byType(PostInfoSheet), findsOneWidget);
      Finder inSheet(Finder f) =>
          find.descendant(of: find.byType(PostInfoSheet), matching: f);
      expect(inSheet(find.text('Facts')), findsOneWidget);
      expect(inSheet(find.byType(BeaconPinnedFactCard)), findsNWidgets(2));
      expect(
        tester.getTopLeft(inSheet(find.text(_keyFact))).dy,
        lessThan(tester.getTopLeft(inSheet(find.text(_glovesFact))).dy),
        reason: 'both facts, in list order',
      );
    });
  });
}
