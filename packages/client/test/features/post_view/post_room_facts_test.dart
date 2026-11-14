// Facts in a Post's Chat (plan D5, D17, R3, R6, §6.6): a Post member pins a
// message as a fact, adds a fact from the attach-menu picker («In this Post»,
// with «Pin your first fact» on an empty list) and quotes facts, all over the
// Post room's own RoomCubit. A Post has one fact visibility, so nothing asks
// or shows it: no choice when pinning, no choice in the add-fact form, no
// public / discussion ribbon on a pinned message, no Make public /
// Discussion only tile. A pinned own message stays a bud source in a Post
// (in a Request it does not). An archived Post's fact actions keep History,
// «Use in another Request or Post» and Copy text, never Edit or Unpin.
// A Request room keeps all of its visibility UI.
//
// Post rooms are mounted the production way: PostViewScreen over a
// ThreadHostCubit with Post capabilities, whose room is a real RoomCubit over
// the real BeaconThreadsCase; only the repositories are fakes, and the
// fact-card repository records what reaches it.

import 'dart:async';

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
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
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/room_fact_authoring.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_fact_composer_sheet.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/graph_trust_write_fixture.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fact_origin_test_support.dart'
    show hasCyrillic, pumpOpener, russianFor;
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit;
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart' show pumpUntil;
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostfacts01';
const _rootId = 'Mpostroot001';
const _mineId = 'Mmine0000001';
const _pinnedId = 'Mpinned00001';
const _pinnedFactId = 'Fpinned00001';
const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Maria');

const _rootBody = 'Who has a ladder for Saturday?';
const _mineBody = 'The key is under the mat by the red door';
const _pinnedBody = 'Meet at the gate at nine';
const _newFactText = 'Ladder is in the shed';

// The strings the person reads.
const _inThisPost = 'In this Post';
const _useElsewhere = 'Use in another Request or Post';
const _pinAsFact = 'Pin as fact';
const _viewPinnedFact = 'View pinned fact';
const _pinFirst = 'Pin your first fact';
const _newFact = 'New fact';
const _whoCanSee = 'Who can see this fact?';
const _choicePublic = 'Public — visible beyond the discussion';
const _choiceDiscussion = 'Discussion only';
const _makePublic = 'Make public';
const _ribbonPublic = 'Pinned · public fact';
const _ribbonDiscussion = 'Pinned · discussion fact';
const _history = 'Edit history';
const _copyText = 'Copy text';
const _editText = 'Edit text';
const _unpin = 'Unpin';

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

BeaconFactCard _fact({
  required String id,
  required String text,
  String? sourceMessageId,
  int visibility = BeaconFactCardVisibilityBits.room,
}) => BeaconFactCard(
  id: id,
  beaconId: _postId,
  factText: text,
  visibility: visibility,
  pinnedBy: _viewer.id,
  pinnedByTitle: _viewer.displayName,
  createdAt: _createdAt,
  status: BeaconFactCardStatusBits.active,
  sourceMessageId: sourceMessageId,
);

/// The pinned message and its fact.
BeaconFactCard _pinnedFact({
  int visibility = BeaconFactCardVisibilityBits.room,
}) => _fact(
  id: _pinnedFactId,
  text: _pinnedBody,
  sourceMessageId: _pinnedId,
  visibility: visibility,
);

typedef _Pin = ({
  String beaconId,
  String factText,
  int visibility,
  String? sourceMessageId,
});

/// The fact-card repository: lists [facts] per beacon, records each pin and
/// keeps the pinned fact, as the server would.
class _FactRepo extends FakeBeaconFactCardRepository {
  _FactRepo([List<BeaconFactCard>? facts]) : facts = [...?facts];

  final List<BeaconFactCard> facts;
  final pins = <_Pin>[];

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async =>
      facts.where((f) => f.beaconId == beaconId).toList();

  @override
  Future<void> pin({
    required String beaconId,
    required String factText,
    required int visibility,
    String? sourceMessageId,
  }) async {
    pins.add((
      beaconId: beaconId,
      factText: factText,
      visibility: visibility,
      sourceMessageId: sourceMessageId,
    ));
    facts.add(
      BeaconFactCard(
        id: 'Fnew0000000${pins.length}',
        beaconId: beaconId,
        factText: factText,
        visibility: visibility,
        pinnedBy: _viewer.id,
        pinnedByTitle: _viewer.displayName,
        createdAt: _now,
        status: BeaconFactCardStatusBits.active,
        sourceMessageId: sourceMessageId,
      ),
    );
  }
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
    env: const Env(),
    logger: Logger('test'),
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

Finder _inRoom(Finder finder) =>
    find.descendant(of: find.byType(BeaconRoomBody), matching: finder);

/// Opens a room message's actions with a secondary click on its text.
Future<void> _openActionsOf(WidgetTester tester, String body) async {
  final target = _inRoom(
    find.descendant(
      of: find.byType(ListView),
      matching: find.textContaining(body, findRichText: true),
    ),
  );
  expect(target, findsWidgets, reason: 'the message «$body» is in the room');
  await tester.tapAt(
    tester.getTopLeft(target.first) + const Offset(8, 8),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await _settle(tester);
  expect(find.byType(BottomSheet), findsWidgets);
}

/// Attach › Fact: the composer's fact picker.
Future<void> _openFactPicker(WidgetTester tester, L10n l10n) async {
  final attach = _inRoom(find.byKey(const ValueKey('attach')));
  expect(attach, findsOneWidget, reason: 'the Post composer offers attach');
  await tester.tap(attach);
  await _settle(tester);
  await tester.tap(find.text(l10n.beaconRoomAttachPickFact).last);
  await _settle(tester);
  expect(find.byType(FactPickerSheet), findsOneWidget);
}

Finder _inPicker(Finder finder) =>
    find.descendant(of: find.byType(FactPickerSheet), matching: finder);

/// Elements of [what] in the same route (sheet) as [anchor].
List<Element> _inRouteOf(WidgetTester tester, Finder anchor, Finder what) {
  expect(anchor, findsWidgets);
  final route = ModalRoute.of(tester.element(anchor.first));
  return what.evaluate().where((e) => ModalRoute.of(e) == route).toList();
}

/// No visibility wording anywhere on screen.
void _expectNoVisibilityChoice(WidgetTester tester) {
  for (final text in [
    _whoCanSee,
    _choicePublic,
    _choiceDiscussion,
    _makePublic,
    _ribbonPublic,
    _ribbonDiscussion,
  ]) {
    expect(find.text(text, findRichText: true), findsNothing, reason: text);
  }
  expect(find.byType(RadioListTile<int>), findsNothing);
}

/// The production fact-card stack (Ferry -> BeaconFactCardRepository and its
/// row mapper); only HTTP is faked. BeaconFactCardPin is recorded and answered
/// as the server does, and the pinned fact is listed by BeaconFactCardList.
final class _FactWire {
  _FactWire._(this.remote, this.repository);

  final RemoteApiService remote;
  final BeaconFactCardRepository repository;
  final pinVariables = <Map<String, dynamic>>[];
  final rows = <Map<String, Object?>>[];

  static Future<_FactWire> start(WidgetTester tester) async {
    late _FactWire wire;
    await tester.runAsync(() async {
      await http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          await remote.setSessionAuth();
          await remote.getAuthToken();
          wire = _FactWire._(remote, BeaconFactCardRepository(remote));
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
          final name = body['operationName'] as String;
          final vars = (body['variables'] as Map).cast<String, dynamic>();
          if (name == 'BeaconFactCardPin') {
            wire.pinVariables.add(vars);
            wire.rows.add({
              '__typename': 'v2_BeaconFactCardRow',
              'id': 'Fwire0000${wire.rows.length + 1}',
              'beaconId': vars['beaconId'],
              'factText': vars['factText'],
              'visibility': vars['visibility'],
              'pinnedBy': _viewer.id,
              'pinnedByTitle': _viewer.displayName,
              'sourceMessageId': vars['sourceMessageId'],
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
            });
          }
          return json({
            'data': switch (name) {
              'BeaconFactCardPin' => {
                '__typename': 'mutation_root',
                'BeaconFactCardPin': true,
              },
              'BeaconFactCardList' => {
                '__typename': 'query_root',
                'BeaconFactCardList': [
                  for (final r in wire.rows)
                    if (r['beaconId'] == vars['beaconId']) r,
                ],
              },
              _ => null,
            },
          });
        }),
      );
    });
    addTearDown(() => tester.runAsync(wire.remote.close));
    return wire;
  }
}

void main() {
  group('Post facts over the real fact-card transport', () {
    testWidgets('«Pin as fact» sends BeaconFactCardPin for this Post and this '
        'message without asking who can see it; the room '
        'lists the fact and the picker shows it under «In this Post»', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final wire = await _FactWire.start(tester);
      final room = await _pumpPost(tester, facts: wire.repository);

      await _openActionsOf(tester, _mineBody);
      expect(find.text(_pinAsFact), findsOneWidget);
      await tester.tap(find.text(_pinAsFact));
      await _settle(tester);

      _expectNoVisibilityChoice(tester);
      expect(wire.pinVariables, hasLength(1));
      expect(wire.pinVariables.single['beaconId'], _postId);
      expect(wire.pinVariables.single['factText'], _mineBody);
      expect(wire.pinVariables.single['sourceMessageId'], _mineId);
      expect(
        room.state.factCards.map((f) => (f.factText, f.sourceMessageId)),
        contains((_mineBody, _mineId)),
        reason: 'the Post room cubit itself reloads the pinned fact',
      );

      await _openFactPicker(tester, l10n);
      expect(_inPicker(find.text(_inThisPost)), findsOneWidget);
      expect(_inPicker(find.text(_mineBody)), findsOneWidget);
    });

    testWidgets('the empty picker opens the add-fact form, which asks no '
        'visibility; Pin sends BeaconFactCardPin for this Post and the fact '
        'joins the Post room and the picker', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final wire = await _FactWire.start(tester);
      final room = await _pumpPost(tester, facts: wire.repository);

      await _openFactPicker(tester, l10n);
      expect(_inPicker(find.text(_pinFirst)), findsOneWidget);
      await tester.tap(_inPicker(find.text(_pinFirst)));
      await _settle(tester);
      expect(find.text(_newFact), findsOneWidget);
      _expectNoVisibilityChoice(tester);

      final field = _inRouteOf(
        tester,
        find.text(_newFact),
        find.byType(TextField),
      );
      await tester.enterText(find.byWidget(field.first.widget), _newFactText);
      await tester.pump();
      await tester.tap(
        find.byKey(TestIds.key(TestIds.beaconFactsComposerSubmit)),
      );
      await _settle(tester);

      expect(find.text(_newFact), findsNothing, reason: 'the form closed');
      expect(wire.pinVariables, hasLength(1));
      expect(wire.pinVariables.single['beaconId'], _postId);
      expect(wire.pinVariables.single['factText'], _newFactText);
      expect(
        room.state.factCards.map((f) => f.factText),
        contains(_newFactText),
      );

      await _openFactPicker(tester, l10n);
      expect(_inPicker(find.text(_newFactText)), findsOneWidget);
    });
  });

  group('pinning a message as a fact in a Post', () {
    testWidgets('the message menu offers «Pin as fact»; it pins at once, '
        'with no visibility choice, into this Post', (tester) async {
      final facts = _FactRepo();
      await _pumpPost(tester, facts: facts);

      await _openActionsOf(tester, _mineBody);
      expect(find.text(_pinAsFact), findsOneWidget);
      await tester.tap(find.text(_pinAsFact));
      await _settle(tester);

      _expectNoVisibilityChoice(tester);
      expect(facts.pins, hasLength(1));
      expect(facts.pins.single.beaconId, _postId);
      expect(facts.pins.single.sourceMessageId, _mineId);
      expect(facts.pins.single.factText, _mineBody);
    });

    testWidgets('the pinned fact then shows in the attach-menu picker, '
        'headed «In this Post»', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final facts = _FactRepo();
      await _pumpPost(tester, facts: facts);

      await _openActionsOf(tester, _mineBody);
      await tester.tap(find.text(_pinAsFact));
      await _settle(tester);

      await _openFactPicker(tester, l10n);
      expect(_inPicker(find.text(_inThisPost)), findsOneWidget);
      expect(_inPicker(find.text(_mineBody)), findsOneWidget);
    });
  });

  group('adding a fact from the picker in a Post', () {
    testWidgets('an empty picker is headed «In this Post» and offers «Pin '
        'your first fact»', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPost(tester, facts: _FactRepo());

      await _openFactPicker(tester, l10n);

      expect(_inPicker(find.text(_inThisPost)), findsOneWidget);
      expect(_inPicker(find.text(_pinFirst)), findsOneWidget);
    });

    testWidgets('the add-fact form shows no visibility choice; Pin reaches '
        'the fact repository for this Post and the fact joins the picker', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final facts = _FactRepo();
      await _pumpPost(tester, facts: facts);

      await _openFactPicker(tester, l10n);
      expect(_inPicker(find.text(_pinFirst)), findsOneWidget);
      await tester.tap(_inPicker(find.text(_pinFirst)));
      await _settle(tester);

      expect(find.byType(FactPickerSheet), findsNothing);
      expect(find.text(_newFact), findsOneWidget);
      _expectNoVisibilityChoice(tester);

      final field = _inRouteOf(
        tester,
        find.text(_newFact),
        find.byType(TextField),
      );
      expect(field, isNotEmpty, reason: 'the form has a text field');
      await tester.enterText(find.byWidget(field.first.widget), _newFactText);
      await tester.pump();
      final submit = find.byKey(TestIds.key(TestIds.beaconFactsComposerSubmit));
      expect(submit, findsOneWidget);
      await tester.tap(submit);
      await _settle(tester);

      expect(find.text(_newFact), findsNothing, reason: 'the form closed');
      expect(facts.pins, hasLength(1));
      expect(facts.pins.single.beaconId, _postId);
      expect(facts.pins.single.factText, _newFactText);

      await _openFactPicker(tester, l10n);
      expect(_inPicker(find.text(_newFactText)), findsOneWidget);
    });
  });

  group('a pinned message in a Post', () {
    final messages = [
      _msg(_rootId, _rootBody),
      _msg(_pinnedId, _pinnedBody, linkedFactCardId: _pinnedFactId),
    ];

    for (final visibility in [
      BeaconFactCardVisibilityBits.room,
      BeaconFactCardVisibilityBits.public,
    ]) {
      testWidgets('shows no visibility ribbon and its fact actions offer no '
          'visibility tile (stored visibility $visibility)', (tester) async {
        await _pumpPost(
          tester,
          facts: _FactRepo([_pinnedFact(visibility: visibility)]),
          messages: messages,
        );

        _expectNoVisibilityChoice(tester);

        await _openActionsOf(tester, _pinnedBody);
        expect(find.text(_viewPinnedFact), findsOneWidget);
        await tester.tap(find.text(_viewPinnedFact));
        await _settle(tester);

        expect(find.text(_editText), findsOneWidget);
        expect(find.text(_useElsewhere), findsOneWidget);
        expect(find.text(_makePublic), findsNothing);
        expect(find.text(_choiceDiscussion), findsNothing);
      });
    }

    testWidgets('own pinned message still offers «Make a request»', (
      tester,
    ) async {
      await _pumpPost(
        tester,
        facts: _FactRepo([_pinnedFact()]),
        messages: messages,
      );

      await _openActionsOf(tester, _pinnedBody);

      expect(find.byKey(const Key('Room.BudRequestAction')), findsOneWidget);
    });
  });

  group('fact actions sheet of a Post fact', () {
    Future<void> openFor(
      WidgetTester tester, {
      required BeaconStatus status,
      Locale locale = const Locale('en'),
    }) async {
      registerRoomCubitProfileCubit(_viewer.id);
      final cubit = _realRoomCubit(
        beaconId: _postId,
        messages: [_msg(_pinnedId, _pinnedBody)],
        facts: _FactRepo([_pinnedFact()]),
        capabilities: const RoomCapabilities.post(),
      );
      addTearDown(cubit.close);
      await tester.runAsync(() => awaitRoomCubitLoad(cubit));
      cubit.syncBeaconStatus(status, authorId: _viewer.id);
      await pumpOpener(
        tester,
        locale: locale,
        open: (ctx) => unawaited(
          showFactActionsSheet(
            ctx,
            cubit: cubit,
            fact: _pinnedFact(),
            isPost: true,
          ),
        ),
      );
    }

    testWidgets('open Post: Edit and Unpin, no Make public / Discussion only', (
      tester,
    ) async {
      await openFor(tester, status: BeaconStatus.open);

      expect(find.text(_editText), findsOneWidget);
      expect(find.text(_unpin), findsOneWidget);
      expect(find.text(_useElsewhere), findsOneWidget);
      expect(find.text(_makePublic), findsNothing);
      expect(find.text(_choiceDiscussion), findsNothing);
    });

    testWidgets('archived Post: History, «Use in another Request or Post» and '
        'Copy text; no Edit, no Unpin', (tester) async {
      await openFor(tester, status: BeaconStatus.closed);

      expect(find.text(_history), findsOneWidget);
      expect(find.text(_useElsewhere), findsOneWidget);
      expect(find.text(_copyText), findsOneWidget);
      expect(find.text(_editText), findsNothing);
      expect(find.text(_unpin), findsNothing);
      expect(find.text(_makePublic), findsNothing);
      expect(find.text(_choiceDiscussion), findsNothing);
    });
  });

  group('Russian, 375x667', () {
    testWidgets('picker, empty state, add-fact form and actions read in '
        'Russian without overflow', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      final facts = _FactRepo();
      await _pumpPost(
        tester,
        facts: facts,
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );
      expect(tester.takeException(), isNull);

      await _openFactPicker(tester, l10n);
      final ruInThisPost = russianFor(_inThisPost);
      expect(hasCyrillic(ruInThisPost), isTrue);
      expect(_inPicker(find.text(ruInThisPost)), findsOneWidget);
      expect(_inPicker(find.text(_inThisPost)), findsNothing);
      expect(
        _inPicker(find.text(l10n.beaconRoomFactPickerPinFirst)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(_inPicker(find.text(l10n.beaconRoomFactPickerPinFirst)));
      await _settle(tester);
      expect(find.text(l10n.beaconFactsComposerTitle), findsOneWidget);
      expect(find.text(l10n.beaconRoomPinFactPublic), findsNothing);
      expect(find.text(l10n.beaconRoomPinFactRoomOnly), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("an archived Post fact's actions read in Russian", (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      registerRoomCubitProfileCubit(_viewer.id);
      final cubit = _realRoomCubit(
        beaconId: _postId,
        messages: [_msg(_pinnedId, _pinnedBody)],
        facts: _FactRepo([_pinnedFact()]),
        capabilities: const RoomCapabilities.post(),
      );
      addTearDown(cubit.close);
      await tester.runAsync(() => awaitRoomCubitLoad(cubit));
      cubit.syncBeaconStatus(BeaconStatus.closed, authorId: _viewer.id);
      await tester.binding.setSurfaceSize(const Size(375, 667));
      await pumpOpener(
        tester,
        locale: const Locale('ru'),
        size: const Size(375, 667),
        open: (ctx) => unawaited(
          showFactActionsSheet(
            ctx,
            cubit: cubit,
            fact: _pinnedFact(),
            isPost: true,
          ),
        ),
      );

      expect(find.text(russianFor(_useElsewhere)), findsOneWidget);
      expect(find.text(_useElsewhere), findsNothing);
      expect(
        find.text(l10n.beaconRoomFactCardActionEditHistory),
        findsOneWidget,
      );
      expect(find.text(l10n.beaconRoomFactCardActionCopy), findsOneWidget);
      expect(find.text(l10n.beaconRoomFactCardActionEdit), findsNothing);
      expect(find.text(l10n.beaconRoomFactCardActionRemove), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Pin as fact» in the message menu pins with no visibility '
        'wording, without overflow', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      final facts = _FactRepo();
      await _pumpPost(
        tester,
        facts: facts,
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      await _openActionsOf(tester, _mineBody);
      expect(find.text(l10n.beaconRoomActionPinFact), findsOneWidget);
      expect(find.text(_pinAsFact), findsNothing);
      await tester.tap(find.text(l10n.beaconRoomActionPinFact));
      await _settle(tester);

      for (final text in [
        l10n.beaconRoomPinFactTitle,
        l10n.beaconRoomPinFactPublic,
        l10n.beaconRoomPinFactRoomOnly,
      ]) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(facts.pins, hasLength(1));
      expect(facts.pins.single.beaconId, _postId);
      expect(tester.takeException(), isNull);
    });

    testWidgets('open Post fact actions: Russian tiles, no visibility '
        'tile, no overflow', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      registerRoomCubitProfileCubit(_viewer.id);
      final cubit = _realRoomCubit(
        beaconId: _postId,
        messages: [_msg(_pinnedId, _pinnedBody)],
        facts: _FactRepo([_pinnedFact()]),
        capabilities: const RoomCapabilities.post(),
      );
      addTearDown(cubit.close);
      await tester.runAsync(() => awaitRoomCubitLoad(cubit));
      cubit.syncBeaconStatus(BeaconStatus.open, authorId: _viewer.id);
      await pumpOpener(
        tester,
        locale: const Locale('ru'),
        size: const Size(375, 667),
        open: (ctx) => unawaited(
          showFactActionsSheet(
            ctx,
            cubit: cubit,
            fact: _pinnedFact(),
            isPost: true,
          ),
        ),
      );

      expect(find.text(russianFor(_useElsewhere)), findsOneWidget);
      expect(find.text(_useElsewhere), findsNothing);
      expect(find.text(l10n.beaconRoomFactCardActionEdit), findsOneWidget);
      expect(find.text(l10n.beaconRoomFactCardActionRemove), findsOneWidget);
      expect(find.text(l10n.beaconRoomFactCardActionMakePublic), findsNothing);
      expect(find.text(l10n.beaconRoomFactCardActionMakePrivate), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('a Request room keeps its visibility UI', () {
    Future<RoomCubit> pumpRequest(
      WidgetTester tester, {
      required _FactRepo facts,
      required List<RoomMessage> messages,
      bool withAddFactForm = false,
    }) async {
      final getIt = GetIt.I;
      await getIt.reset();
      addTearDown(getIt.reset);
      final profileCubit = _ProfileCubit(_viewer);
      getIt
        ..registerSingleton<ProfileCubit>(profileCubit)
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        );
      final cubit = _realRoomCubit(
        beaconId: _postId,
        messages: messages,
        facts: facts,
        capabilities: const RoomCapabilities.request(),
      );
      addTearDown(cubit.close);
      await tester.runAsync(() => awaitRoomCubitLoad(cubit));
      cubit.syncBeaconStatus(BeaconStatus.open, authorId: _viewer.id);
      // The Request route's add-fact form (BeaconViewScope provides it).
      BeaconViewCubit? viewCubit;
      if (withAddFactForm) {
        viewCubit = (await tester.runAsync(() async {
          final c = BeaconViewCubit(
            id: _postId,
            myProfile: _viewer,
            beaconViewCase: buildTestBeaconViewCase(
              beaconRepo: TrackingBeaconRepository()
                ..fetchByIdHandler = (_) async => Beacon(
                  id: _postId,
                  title: 'Garden day',
                  createdAt: _createdAt,
                  updatedAt: _createdAt,
                  author: _viewer,
                ),
              factCardsRepo: FakeBeaconViewFactCardRepository(),
              roomRepo: FakeBeaconViewRoomRepository(),
            ),
            effects: FakeUiEffectPort(),
          );
          await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
          return c;
        }))!;
        addTearDown(viewCubit.close);
      }
      const size = Size(700, 900);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            if (viewCubit != null) ...[
              BlocProvider<BeaconViewCubit>.value(value: viewCubit),
              RepositoryProvider<RoomFactAuthoring>.value(
                value: BeaconViewRoomFactAuthoring(viewCubit),
              ),
            ],
            BlocProvider<RoomCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(
              value: RoomBodyHarnessPresenceCubit(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const MediaQuery(
              data: MediaQueryData(size: size),
              child: TenturaResponsiveScope(
                child: Scaffold(body: BeaconRoomBody()),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      return cubit;
    }

    final messages = [
      _msg(_pinnedId, _pinnedBody, linkedFactCardId: _pinnedFactId),
      _msg(_mineId, _mineBody),
    ];

    testWidgets('a pinned message shows the discussion ribbon; its fact '
        'actions offer Make public and «Use in another Request or Post»; '
        'no «Make a request» on it', (tester) async {
      await pumpRequest(
        tester,
        facts: _FactRepo([_pinnedFact()]),
        messages: messages,
      );

      expect(find.text(_ribbonDiscussion, findRichText: true), findsWidgets);

      await _openActionsOf(tester, _pinnedBody);
      expect(find.byKey(const Key('Room.BudRequestAction')), findsNothing);
      await tester.tap(find.text(_viewPinnedFact));
      await _settle(tester);

      expect(find.text(_makePublic), findsOneWidget);
      expect(find.text(_useElsewhere), findsOneWidget);
    });

    testWidgets('a public fact offers Discussion only', (tester) async {
      await pumpRequest(
        tester,
        facts: _FactRepo([
          _pinnedFact(visibility: BeaconFactCardVisibilityBits.public),
        ]),
        messages: messages,
      );

      expect(find.text(_ribbonPublic, findRichText: true), findsWidgets);
      await _openActionsOf(tester, _pinnedBody);
      await tester.tap(find.text(_viewPinnedFact));
      await _settle(tester);

      expect(find.text(_choiceDiscussion), findsOneWidget);
    });

    testWidgets('pinning a message still asks who can see the fact', (
      tester,
    ) async {
      await pumpRequest(tester, facts: _FactRepo(), messages: messages);

      await _openActionsOf(tester, _mineBody);
      await tester.tap(find.text(_pinAsFact));
      await _settle(tester);

      expect(find.text(_whoCanSee), findsOneWidget);
      expect(find.text(_choicePublic), findsOneWidget);
      expect(find.text(_choiceDiscussion), findsOneWidget);
    });

    testWidgets('the add-fact form still asks who can see the fact', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await pumpRequest(
        tester,
        facts: _FactRepo(),
        messages: messages,
        withAddFactForm: true,
      );

      await _openFactPicker(tester, l10n);
      expect(find.text(_inThisPost), findsNothing);
      expect(_inPicker(find.text(_pinFirst)), findsOneWidget);
      await tester.tap(_inPicker(find.text(_pinFirst)));
      await _settle(tester);

      expect(find.text(_newFact), findsOneWidget);
      expect(find.text(_choicePublic), findsOneWidget);
      expect(find.text(_choiceDiscussion), findsOneWidget);
    });

    testWidgets('the attach-menu picker is not headed «In this Post»', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await pumpRequest(tester, facts: _FactRepo(), messages: messages);

      await _openFactPicker(tester, l10n);

      expect(find.text(_inThisPost), findsNothing);
    });
  });

  group('strings', () {
    test('«In this Post» and the renamed action have Russian entries', () {
      for (final en in [_inThisPost, _useElsewhere]) {
        expect(hasCyrillic(russianFor(en)), isTrue, reason: en);
      }
    });

    test('the destination empty text names Posts in EN and RU', () async {
      final en = await L10n.delegate.load(const Locale('en'));
      final ru = await L10n.delegate.load(const Locale('ru'));
      expect(en.beaconFactCopyEmpty, matches(RegExp(r'\bPosts?\b')));
      expect(
        ru.beaconFactCopyEmpty.toLowerCase(),
        matches(RegExp('(^|[^а-яё])пост')),
      );
    });

    test('the Post row remaining time is worded in EN and RU', () async {
      // The row reuses the Post lifetime wording (postRemaining*), so each
      // bucket must read in both languages.
      final en = await L10n.delegate.load(const Locale('en'));
      final ru = await L10n.delegate.load(const Locale('ru'));
      for (final d in const [
        Duration(minutes: 5),
        Duration(hours: 3),
        Duration(days: 2),
      ]) {
        expect(hasCyrillic(postRemainingLabel(en, d)), isFalse);
        expect(hasCyrillic(postRemainingLabel(ru, d)), isTrue);
      }
    });
  });
}
