import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/components/tentura_underline_tabs.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/screen/thread_detail_screen.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/item_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_coordination_item_case.dart';
import 'room_cubit_fakes.dart';

const _kBeaconId = 'b-adaptive-test';
const _kAuthorId = 'author-adaptive';
const _kHelperId = 'helper-adaptive';
final _kSeenAt = DateTime.utc(2026, 8, 14, 10);
final _kNow = DateTime.utc(2026, 8, 14, 12);

const _kCompact = Size(390, 844);
const _kRegular = Size(720, 900);
const _kExpanded = Size(1280, 900);
const _kEmbeddedSplit = Size(720, 900);
const _kEmbeddedStack = Size(559, 900);

class _MockRouteData extends Mock implements RouteData {
  _MockRouteData(this.name);

  @override
  final String name;
}

class _HarnessRouter extends Mock implements StackRouter {
  int pushCount = 0;
  int popCount = 0;
  PageRouteInfo? lastPush;
  final List<String> replacedPaths = [];
  RouteData? currentChild;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    lastPush = route;
    currentChild = _MockRouteData(ThreadDetailRoute.name);
    return null;
  }

  @override
  Future<T?> replacePath<T extends Object?>(
    String path, {
    bool includeAncestors = false,
    bool includePrefixMatches = true,
  }) async {
    replacedPaths.add(path);
    return null;
  }

  @override
  void pop<T extends Object?>([T? result]) {
    popCount++;
    currentChild = null;
  }

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) =>
      false;
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _HarnessBeaconViewCubit extends Mock implements BeaconViewCubit {
  _HarnessBeaconViewCubit(this._state);

  BeaconViewState _state;

  void setState(BeaconViewState value) => _state = value;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream.value(_state);
}

class _HarnessThreadsCubit extends Mock implements ThreadsCubit {
  _HarnessThreadsCubit(this._state) {
    _controller = StreamController<ThreadsState>.broadcast();
    _controller.add(_state);
  }

  ThreadsState _state;
  late final StreamController<ThreadsState> _controller;

  void emitState(ThreadsState value) {
    _state = value;
    _controller.add(_state);
  }

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => _controller.stream;

  @override
  Future<void> fetch({bool silent = false}) async {}

  @override
  void setActiveForMeOnly(bool value) {
    emitState(_state.copyWith(activeForMeOnly: value));
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class RecordingRoomCubit extends Mock implements RoomCubit {
  RecordingRoomCubit({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
  }) : closeCompleter = Completer<void>(),
       _state = RoomState(
         beaconId: beaconId,
         threadItemId: threadItemId,
         unreadAnchorAt: initialUnreadAnchorAt,
       );

  final RoomState _state;
  final Completer<void> closeCompleter;
  int closeCallCount = 0;
  bool gateClose = false;
  bool _isClosed = false;

  String? lastScrollMessageId;
  String? lastScrollCoordinationItemId;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream.value(_state);

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> close() async {
    closeCallCount++;
    if (!gateClose && !closeCompleter.isCompleted) {
      closeCompleter.complete();
    }
    await closeCompleter.future;
    _isClosed = true;
  }

  @override
  Future<void> markReadToBottom() async {}

  @override
  Future<void> load() async {}

  @override
  void prepareThreadScroll({String? messageId, String? coordinationItemId}) {
    lastScrollMessageId = messageId;
    lastScrollCoordinationItemId = coordinationItemId;
  }
}

class RoomCubitFactoryRecorder {
  final List<RecordingRoomCubit> created = [];

  RecordingRoomCubit call({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
  }) {
    final cubit = RecordingRoomCubit(
      beaconId: beaconId,
      threadItemId: threadItemId,
      initialUnreadAnchorAt: initialUnreadAnchorAt,
    );
    created.add(cubit);
    return cubit;
  }
}

ThreadHostCubit _host({RoomCubitFactoryRecorder? recorder}) {
  final factoryRecorder = recorder ?? RoomCubitFactoryRecorder();
  return ThreadHostCubit(
    beaconId: _kBeaconId,
    roomCubitFactory: ({
      required String beaconId,
      String? threadItemId,
      DateTime? initialUnreadAnchorAt,
    }) =>
        factoryRecorder.call(
          beaconId: beaconId,
          threadItemId: threadItemId,
          initialUnreadAnchorAt: initialUnreadAnchorAt,
        ),
  );
}

CoordinationItem _item({
  required String id,
  CoordinationItemKind kind = CoordinationItemKind.ask,
  CoordinationItemStatus status = CoordinationItemStatus.open,
  bool published = true,
  String creatorId = _kAuthorId,
  String? targetPersonId = _kHelperId,
  int unreadCount = 0,
  String body = 'Semantic body',
  String? linkedMessageId,
}) =>
    CoordinationItem(
      id: id,
      beaconId: _kBeaconId,
      kind: kind,
      status: status,
      creatorId: creatorId,
      createdAt: _kNow,
      updatedAt: _kNow,
      published: published,
      targetPersonId: targetPersonId,
      body: body,
      unreadCount: unreadCount,
      linkedMessageId: linkedMessageId,
    );

RequestThread _generalThread({
  int unreadCount = 0,
  DateTime? lastSeenAt,
}) =>
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      unreadCount: unreadCount,
      lastSeenAt: lastSeenAt ?? _kSeenAt,
    );

RequestThread _semanticThread({
  required CoordinationItem item,
  int unreadCount = 0,
  DateTime? lastSeenAt,
}) =>
    RequestThread(
      threadId: item.id,
      kind: switch (item.kind) {
        CoordinationItemKind.ask => RequestThreadKind.ask,
        CoordinationItemKind.promise => RequestThreadKind.promise,
        CoordinationItemKind.blocker => RequestThreadKind.blocker,
        CoordinationItemKind.plan => RequestThreadKind.ask,
      },
      unreadCount: unreadCount,
      item: item,
      lastSeenAt: lastSeenAt ?? _kSeenAt,
    );

BeaconViewState _authorBeaconState({
  List<BeaconActivityEvent> roomActivityEvents = const [],
  bool beaconContentLoaded = true,
}) =>
    BeaconViewState(
      beacon: Beacon(
        id: _kBeaconId,
        title: 'Adaptive request',
        author: const Profile(id: _kAuthorId, displayName: 'Author'),
        createdAt: _kNow,
        updatedAt: _kNow,
      ),
      myProfile: const Profile(id: _kAuthorId, displayName: 'Author'),
      beaconContentLoaded: beaconContentLoaded,
      roomParticipantsLoaded: true,
      roomParticipants: [
        BeaconParticipant(
          id: 'p-author',
          beaconId: _kBeaconId,
          userId: _kAuthorId,
          role: 0,
          status: 0,
          roomAccess: RoomAccessBits.admitted,
          createdAt: _kNow,
          updatedAt: _kNow,
        ),
      ],
      roomActivityEvents: roomActivityEvents,
    );

BeaconViewState _itemOnlyParticipantState({
  required String participantId,
  bool waitingForAdmission = false,
  bool denied = false,
}) {
  return BeaconViewState(
    beacon: Beacon(
      id: _kBeaconId,
      title: 'Adaptive request',
      author: const Profile(id: _kAuthorId, displayName: 'Author'),
      createdAt: _kNow,
      updatedAt: _kNow,
    ),
    myProfile: Profile(id: participantId, displayName: 'Participant'),
    beaconContentLoaded: true,
    roomParticipantsLoaded: true,
    roomParticipants: [
      BeaconParticipant(
        id: 'p-$participantId',
        beaconId: _kBeaconId,
        userId: participantId,
        role: 0,
        status: 0,
        roomAccess: RoomAccessBits.none,
        createdAt: _kNow,
        updatedAt: _kNow,
      ),
    ],
    helpOffers: waitingForAdmission || denied
        ? [
            TimelineHelpOffer(
              user: Profile(id: participantId, displayName: 'Participant'),
              message: 'Offered help',
              createdAt: _kNow,
              updatedAt: _kNow,
              coordinationResponse: denied
                  ? CoordinationResponseType.notSuitable
                  : null,
            ),
          ]
        : const [],
    isHelpOffered: waitingForAdmission || denied,
  );
}

ThreadsState _threadsState({
  required List<RequestThread> threads,
  Map<String, int>? resolvedUnreadByThreadId,
  String myUserId = _kAuthorId,
}) =>
    ThreadsState(
      threads: threads,
      resolvedUnreadByThreadId: resolvedUnreadByThreadId ?? const {},
      myUserId: myUserId,
      status: const StateIsSuccess(),
    );

class _Harness {
  _Harness({
    required this.router,
    required this.beaconCubit,
    required this.threadsCubit,
    required this.host,
    required this.recorder,
    required this.beaconState,
    required this.threadsState,
    this.onRequestThreadRoute,
    this.embedded = false,
    this.embeddedWidth,
  });

  final _HarnessRouter router;
  final _HarnessBeaconViewCubit beaconCubit;
  final _HarnessThreadsCubit threadsCubit;
  final ThreadHostCubit host;
  final RoomCubitFactoryRecorder recorder;
  final BeaconViewState beaconState;
  final ThreadsState threadsState;
  final void Function(String threadId, String? messageId)? onRequestThreadRoute;
  final bool embedded;
  final double? embeddedWidth;
}

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  required Size size,
  required BeaconViewState beaconState,
  required ThreadsState threadsState,
  ThreadHostCubit? host,
  RoomCubitFactoryRecorder? recorder,
  _HarnessRouter? router,
  bool embedded = false,
  double? embeddedWidth,
  void Function(String threadId, String? messageId)? onRequestThreadRoute,
}) async {
  final harnessRecorder = recorder ?? RoomCubitFactoryRecorder();
  final harnessHost = host ?? _host(recorder: harnessRecorder);
  final harnessRouter = router ?? _HarnessRouter();
  final beaconCubit = _HarnessBeaconViewCubit(beaconState);
  final threadsCubit = _HarnessThreadsCubit(
    threadsState.copyWith(status: const StateIsLoading()),
  );

  await _setupGetIt(profile: beaconState.myProfile);

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final screen = BeaconViewScreen(
    id: _kBeaconId,
    embedded: embedded,
    onRequestThreadRoute: onRequestThreadRoute,
  );

  Widget child = MultiBlocProvider(
    providers: [
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      BlocProvider<BeaconViewCubit>.value(value: beaconCubit),
      BlocProvider<ThreadsCubit>.value(value: threadsCubit),
      BlocProvider<ThreadHostCubit>.value(value: harnessHost),
      BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(beaconState.myProfile),
      ),
    ],
    child: Scaffold(body: screen),
  );

  if (embeddedWidth != null) {
    child = Center(
      child: SizedBox(width: embeddedWidth, child: child),
    );
  }

  final effectiveSize = embeddedWidth != null
      ? Size(embeddedWidth, size.height)
      : size;

  await tester.pumpWidget(
    StackRouterScope(
      controller: harnessRouter,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: MediaQueryData(size: effectiveSize),
          child: TenturaResponsiveScope(child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  threadsCubit.emitState(threadsState);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  return _Harness(
    router: harnessRouter,
    beaconCubit: beaconCubit,
    threadsCubit: threadsCubit,
    host: harnessHost,
    recorder: harnessRecorder,
    beaconState: beaconState,
    threadsState: threadsState,
    onRequestThreadRoute: onRequestThreadRoute,
    embedded: embedded,
    embeddedWidth: embeddedWidth,
  );
}

Future<void> _resizeHarness(WidgetTester tester, _Harness harness, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await _pumpHarness(
    tester,
    size: size,
    beaconState: harness.beaconState,
    threadsState: harness.threadsState,
    host: harness.host,
    recorder: harness.recorder,
    router: harness.router,
    embedded: harness.embedded,
    embeddedWidth: harness.embeddedWidth,
    onRequestThreadRoute: harness.onRequestThreadRoute,
  );
}

Future<void> _setupGetIt({Profile? profile}) async {
  final getIt = GetIt.I;
  if (getIt.isRegistered<CoordinationItemCase>()) {
    await getIt.unregister<CoordinationItemCase>();
  }
  getIt.registerSingleton<CoordinationItemCase>(
    const FakeCoordinationItemCaseForRoom(),
  );
  if (!getIt.isRegistered<ImageRepository>()) {
    getIt.registerSingleton<ImageRepository>(ImageRepository());
  }
  if (!getIt.isRegistered<ClipboardImageRepository>()) {
    getIt.registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );
  }
  if (getIt.isRegistered<ProfileCubit>()) {
    await getIt.unregister<ProfileCubit>();
  }
  getIt.registerSingleton<ProfileCubit>(
    _MockProfileCubit(profile ?? const Profile(id: _kAuthorId, displayName: 'Author')),
  );
  if (getIt.isRegistered<BeaconThreadsCase>()) {
    await getIt.unregister<BeaconThreadsCase>();
  }
  getIt.registerSingleton<BeaconThreadsCase>(
    roomCubitMakeCase(
      FakeBeaconThreadsRepository(userId: profile?.id ?? _kAuthorId),
    ),
  );
  if (getIt.isRegistered<UiEffectPort>()) {
    await getIt.unregister<UiEffectPort>();
  }
  getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
}

bool _itemCardSelected(WidgetTester tester, String threadId) {
  final card = tester.widget<ItemCard>(
    find.byKey(TestIds.key(TestIds.requestThread(threadId))),
  );
  return card.isSelected;
}

TenturaUnderlineTabs _tabs(WidgetTester tester) =>
    tester.widget<TenturaUnderlineTabs>(find.byType(TenturaUnderlineTabs));

class _ResizableMediaQuery extends StatefulWidget {
  const _ResizableMediaQuery({required this.child, required this.size, super.key});

  final Widget child;
  final Size size;

  @override
  State<_ResizableMediaQuery> createState() => _ResizableMediaQueryState();
}

class _ResizableMediaQueryState extends State<_ResizableMediaQuery> {
  late Size _size;

  @override
  void initState() {
    super.initState();
    _size = widget.size;
  }

  void resize(Size size) => setState(() => _size = size);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: _size),
      child: TenturaResponsiveScope(child: widget.child),
    );
  }
}

BeaconActivityEvent _coordinationEvent({
  required CoordinationItemKind kind,
  required String itemId,
  String? sourceMessageId,
  int eventKind = 1,
}) =>
    BeaconActivityEvent(
      id: 'evt-$itemId',
      beaconId: _kBeaconId,
      visibility: 1,
      type: kind.value * 100 + eventKind,
      createdAt: _kNow,
      actorId: _kAuthorId,
      coordinationItemId: itemId,
      sourceMessageId: sourceMessageId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await _setupGetIt();
  });

  tearDown(() async {
    final getIt = GetIt.I;
    if (getIt.isRegistered<CoordinationItemCase>()) {
      await getIt.unregister<CoordinationItemCase>();
    }
    if (getIt.isRegistered<ProfileCubit>()) {
      await getIt.unregister<ProfileCubit>();
    }
    if (getIt.isRegistered<BeaconThreadsCase>()) {
      await getIt.unregister<BeaconThreadsCase>();
    }
    if (getIt.isRegistered<UiEffectPort>()) {
      await getIt.unregister<UiEffectPort>();
    }
  });

  group('compact adaptive', () {
    testWidgets('Threads is tab 0; General row 0; semantic push', (
      tester,
    ) async {
      final semantic = _item(id: 'ask-compact');
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: semantic)],
      );
      final harness = await _pumpHarness(
        tester,
        size: _kCompact,
        beaconState: _authorBeaconState(),
        threadsState: threads,
      );

      expect(_tabs(tester).selectedIndex, 0);
      expect(
        find.byKey(
          TestIds.key(TestIds.requestThread(RequestThread.generalId)),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.requestThread(semantic.id))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.router.pushCount, 1);
      expect(harness.router.lastPush, isA<ThreadDetailRoute>());
    });

    testWidgets('General selection uses null threadItemId in RoomCubit', (
      tester,
    ) async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final threads = _threadsState(threads: [_generalThread()]);
      await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: _authorBeaconState(),
        threadsState: threads,
        host: host,
        recorder: recorder,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(recorder.created, hasLength(1));
      expect(recorder.created.single.state.threadItemId, isNull);
    });

    testWidgets('draft row opens composer and never navigates', (tester) async {
      final draft = _item(
        id: 'draft-compact',
        published: false,
        body: 'Draft compact body',
      );
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: draft)],
      );
      final harness = await _pumpHarness(
        tester,
        size: _kCompact,
        beaconState: _authorBeaconState(),
        threadsState: threads,
      );

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.threadDraftsFoldTitle(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Draft compact body'));
      await tester.pumpAndSettle();

      expect(harness.router.pushCount, 0);
      expect(
        find.byKey(TestIds.key(TestIds.coordinationComposerBody)),
        findsOneWidget,
      );
    });
  });

  group('regular adaptive', () {
    testWidgets('push/pop like compact with no split or selected residue', (
      tester,
    ) async {
      final semantic = _item(id: 'ask-regular');
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: semantic)],
      );
      final harness = await _pumpHarness(
        tester,
        size: _kRegular,
        beaconState: _authorBeaconState(),
        threadsState: threads,
      );

      expect(find.byType(ThreadDetail), findsNothing);

      await tester.tap(
        find.byKey(TestIds.key(TestIds.requestThread(semantic.id))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(harness.router.pushCount, 1);

      harness.router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_itemCardSelected(tester, semantic.id), isFalse);
      expect(_itemCardSelected(tester, RequestThread.generalId), isFalse);
    });
  });

  group('expanded adaptive', () {
    testWidgets('preselects first row; pane persists across People/Log', (
      tester,
    ) async {
      final semantic = _item(id: 'ask-expanded-a');
      final other = _item(id: 'ask-expanded-b', body: 'Second body');
      final threads = _threadsState(
        threads: [
          _generalThread(),
          _semanticThread(item: semantic),
          _semanticThread(item: other),
        ],
      );
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final harness = await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: _authorBeaconState(),
        threadsState: threads,
        host: host,
        recorder: recorder,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(host.state.openThreadId, RequestThread.generalId);
      expect(find.byType(ThreadDetail), findsOneWidget);
      expect(_itemCardSelected(tester, RequestThread.generalId), isTrue);

      await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabPeople)));
      await tester.pumpAndSettle();
      expect(find.byType(ThreadDetail), findsOneWidget);

      await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabLog)));
      await tester.pumpAndSettle();
      expect(find.byType(ThreadDetail), findsOneWidget);

      expect(harness.router.pushCount, 0);
      expect(
        harness.router.replacedPaths.any(
          (p) =>
              p.contains('tab=${kBeaconViewTabThreads}') &&
              p.contains('thread=${RequestThread.generalId}'),
        ),
        isTrue,
      );
    });

    testWidgets('row switch awaits close; indicator moves; no stacked detail', (
      tester,
    ) async {
      final first = _item(id: 'ask-switch-a');
      final second = _item(id: 'ask-switch-b', body: 'Switch target');
      final threads = _threadsState(
        threads: [
          _generalThread(),
          _semanticThread(item: first),
          _semanticThread(item: second),
        ],
      );
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final harness = await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: _authorBeaconState(),
        threadsState: threads,
        host: host,
        recorder: recorder,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final firstCubit = recorder.created.single;
      firstCubit.gateClose = true;

      await tester.tap(find.byKey(TestIds.key(TestIds.requestThread(second.id))));
      await tester.pump();
      expect(recorder.created, hasLength(1));
      expect(host.state.switching, isTrue);

      firstCubit.closeCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(recorder.created, hasLength(2));
      expect(host.state.openThreadId, second.id);
      expect(_itemCardSelected(tester, second.id), isTrue);
      expect(_itemCardSelected(tester, first.id), isFalse);
      expect(harness.router.pushCount, 0);
    });
  });

  group('resize transitions', () {
    testWidgets('expanded→compact pushes after dependency change, not layout', (
      tester,
    ) async {
      final threads = _threadsState(
        threads: [
          _generalThread(),
          _semanticThread(item: _item(id: 'resize-item')),
        ],
      );
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final harness = await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: _authorBeaconState(),
        threadsState: threads,
        host: host,
        recorder: recorder,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.state.openThreadId, isNotNull);

      final pushBeforeResize = harness.router.pushCount;
      await _resizeHarness(tester, harness, _kCompact);
      await tester.pump();
      await tester.pump();
      expect(harness.router.pushCount, pushBeforeResize + 1);
    });

    testWidgets('compact detail→expanded pops once into split', (tester) async {
      final threads = _threadsState(
        threads: [
          _generalThread(),
          _semanticThread(item: _item(id: 'resize-pop')),
        ],
      );
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      await host.select(_generalThread());
      final router = _HarnessRouter();
      await _setupGetIt();
      final mediaKey = GlobalKey<_ResizableMediaQueryState>();

      await tester.pumpWidget(
        StackRouterScope(
          controller: router,
          stateHash: 0,
          child: MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('en'),
            home: _ResizableMediaQuery(
              key: mediaKey,
              size: _kCompact,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ThreadsCubit>.value(
                    value: _HarnessThreadsCubit(threads),
                  ),
                  BlocProvider<ThreadHostCubit>.value(value: host),
                  BlocProvider<BeaconViewCubit>.value(
                    value: _HarnessBeaconViewCubit(_authorBeaconState()),
                  ),
                  BlocProvider<ProfileCubit>.value(
                    value: _MockProfileCubit(
                      const Profile(id: _kAuthorId, displayName: 'Author'),
                    ),
                  ),
                ],
                child: ThreadDetailScreen(
                  beaconId: _kBeaconId,
                  threadId: RequestThread.generalId,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      mediaKey.currentState!.resize(_kExpanded);
      await tester.pump();
      expect(router.popCount, 0);
      await tester.pump();
      expect(router.popCount, 1);
    });

    testWidgets('rapid resize does not double-push or double-pop', (
      tester,
    ) async {
      final threads = _threadsState(
        threads: [
          _generalThread(),
          _semanticThread(item: _item(id: 'rapid-resize')),
        ],
      );
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final harness = await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: _authorBeaconState(),
        threadsState: threads,
        host: host,
        recorder: recorder,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      for (var i = 0; i < 4; i++) {
        await _resizeHarness(
          tester,
          harness,
          i.isEven ? _kCompact : _kExpanded,
        );
        await tester.pump();
        await tester.pump();
      }

      expect(harness.router.pushCount, lessThanOrEqualTo(2));
      expect(harness.router.popCount, lessThanOrEqualTo(2));
      expect(host.state.selectionGeneration, greaterThan(0));
    });
  });

  group('item-only authorization fixture', () {
    testWidgets('participant sees semantic row without General', (tester) async {
      final participantId = _kHelperId;
      final item = _item(
        id: 'item-only-thread',
        creatorId: participantId,
        targetPersonId: _kAuthorId,
      );
      final threads = _threadsState(
        threads: [_semanticThread(item: item)],
        myUserId: participantId,
      );
      await _pumpHarness(
        tester,
        size: _kCompact,
        beaconState: _itemOnlyParticipantState(participantId: participantId),
        threadsState: threads,
      );

      expect(
        find.byKey(
          TestIds.key(TestIds.requestThread(RequestThread.generalId)),
        ),
        findsNothing,
      );
      expect(
        find.byKey(TestIds.key(TestIds.requestThread(item.id))),
        findsOneWidget,
      );
    });

    testWidgets('unknown thread id falls back to first accessible row', (
      tester,
    ) async {
      final item = _item(id: 'fallback-thread');
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: item)],
      );
      final host = _host();
      await _setupGetIt();
      await tester.binding.setSurfaceSize(_kCompact);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        StackRouterScope(
          controller: _HarnessRouter(),
          stateHash: 0,
          child: MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('en'),
            home: MediaQuery(
              data: const MediaQueryData(size: _kCompact),
              child: TenturaResponsiveScope(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
                    BlocProvider<ThreadsCubit>.value(
                      value: _HarnessThreadsCubit(threads),
                    ),
                    BlocProvider<ThreadHostCubit>.value(value: host),
                    BlocProvider<BeaconViewCubit>.value(
                      value: _HarnessBeaconViewCubit(_authorBeaconState()),
                    ),
                    BlocProvider<ProfileCubit>.value(
                      value: _MockProfileCubit(
                        const Profile(id: _kAuthorId, displayName: 'Author'),
                      ),
                    ),
                  ],
                  child: ThreadDetailScreen(
                    beaconId: _kBeaconId,
                    threadId: 'unknown-thread',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(host.state.openThreadId, RequestThread.generalId);
    });

    testWidgets('empty accessible set shows admission placeholder', (
      tester,
    ) async {
      final threads = _threadsState(threads: [], myUserId: _kHelperId);
      await _setupGetIt(
        profile: const Profile(id: _kHelperId, displayName: 'Helper'),
      );
      await tester.pumpWidget(
        StackRouterScope(
          controller: _HarnessRouter(),
          stateHash: 0,
          child: MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('en'),
            home: MediaQuery(
              data: const MediaQueryData(size: _kCompact),
              child: TenturaResponsiveScope(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
                    BlocProvider<ThreadsCubit>.value(
                      value: _HarnessThreadsCubit(threads),
                    ),
                    BlocProvider<ThreadHostCubit>.value(value: _host()),
                    BlocProvider<BeaconViewCubit>.value(
                      value: _HarnessBeaconViewCubit(
                        _itemOnlyParticipantState(
                          participantId: _kHelperId,
                          waitingForAdmission: true,
                        ),
                      ),
                    ),
                    BlocProvider<ProfileCubit>.value(
                      value: _MockProfileCubit(
                        const Profile(id: _kHelperId, displayName: 'Helper'),
                      ),
                    ),
                  ],
                  child: ThreadDetailScreen(
                    beaconId: _kBeaconId,
                    threadId: 'missing',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);
    });
  });

  group('unread adaptive', () {
    testWidgets('tab badge totals General plus active rows only', (tester) async {
      final active = _item(id: 'unread-active', unreadCount: 4);
      final closed = _item(
        id: 'unread-closed',
        status: CoordinationItemStatus.resolved,
        unreadCount: 7,
      );
      final threads = _threadsState(
        threads: [
          _generalThread(unreadCount: 1),
          _semanticThread(item: active, unreadCount: 4),
          _semanticThread(item: closed, unreadCount: 7),
        ],
        resolvedUnreadByThreadId: {
          RequestThread.generalId: 1,
          active.id: 4,
          closed.id: 7,
        },
      );
      await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: _authorBeaconState(),
        threadsState: threads,
      );

      expect(_tabs(tester).badges?[0], 5);
    });

    testWidgets('closed-thread unread stored but excluded from tab badge', (
      tester,
    ) async {
      final closed = _item(
        id: 'unread-closed-fold',
        status: CoordinationItemStatus.resolved,
        body: 'Closed unread body',
        unreadCount: 3,
      );
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: closed, unreadCount: 3)],
        resolvedUnreadByThreadId: {closed.id: 3},
      );
      final harness = await _pumpHarness(
        tester,
        size: _kCompact,
        beaconState: _authorBeaconState(),
        threadsState: threads,
      );

      expect(_tabs(tester).badges?[0], isNull);
      expect(
        harness.threadsCubit.state.resolvedUnreadFor(
          harness.threadsCubit.state.closed.single,
        ),
        3,
      );
    });

    testWidgets('optimistic read suppresses badge without flicker during close', (
      tester,
    ) async {
      final general = _generalThread(unreadCount: 2);
      final threads = _threadsState(
        threads: [general, _semanticThread(item: _item(id: 'unread-switch'))],
        resolvedUnreadByThreadId: {RequestThread.generalId: 2},
      );
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final harness = await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: _authorBeaconState(),
        threadsState: threads,
        host: host,
        recorder: recorder,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      harness.threadsCubit.emitState(
        threads.copyWith(
          resolvedUnreadByThreadId: {RequestThread.generalId: 0},
        ),
      );
      await tester.pump();
      expect(_tabs(tester).badges?[0], isNull);

      final owned = recorder.created.single;
      owned.gateClose = true;
      await tester.tap(
        find.byKey(TestIds.key(TestIds.requestThread('unread-switch'))),
      );
      await tester.pump();
      expect(_tabs(tester).badges?[0], isNull);
      owned.closeCompleter.complete();
      await tester.pump();
      expect(_tabs(tester).badges?[0], isNull);
    });
  });

  group('Log adaptive', () {
    testWidgets('ask row focuses semantic thread', (tester) async {
      final ask = _item(id: 'log-ask');
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: ask)],
      );
      final beacon = _authorBeaconState(
        roomActivityEvents: [
          _coordinationEvent(kind: CoordinationItemKind.ask, itemId: ask.id),
        ],
      );
      await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: beacon,
        threadsState: threads,
      );

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabLog)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.textContaining(l10n.coordinationSemanticAskOpened));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_tabs(tester).selectedIndex, 0);
      expect(
        find.byKey(TestIds.key(TestIds.requestThread(ask.id))),
        findsOneWidget,
      );
    });

    testWidgets('plan row opens General and scrolls to sourceMessageId', (
      tester,
    ) async {
      const planId = 'log-plan';
      const messageId = 'msg-plan-anchor';
      final plan = _item(
        id: planId,
        kind: CoordinationItemKind.plan,
        linkedMessageId: messageId,
      );
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: plan)],
      );
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final beacon = _authorBeaconState(
        roomActivityEvents: [
          _coordinationEvent(
            kind: CoordinationItemKind.plan,
            itemId: planId,
            sourceMessageId: messageId,
          ),
        ],
      );
      await _pumpHarness(
        tester,
        size: _kExpanded,
        beaconState: beacon,
        threadsState: threads,
        host: host,
        recorder: recorder,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabLog)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(l10n.coordinationSemanticPlanOpened).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(host.state.openThreadId, RequestThread.generalId);
      final roomCubit = recorder.created.last;
      expect(roomCubit.lastScrollMessageId, messageId);
      expect(roomCubit.lastScrollCoordinationItemId, planId);
    });
  });

  group('My Work embedded adaptive', () {
    testWidgets('below pane threshold routes via callback', (tester) async {
      final semantic = _item(id: 'embedded-stack');
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: semantic)],
      );
      String? routedThreadId;
      await _pumpHarness(
        tester,
        size: _kExpanded,
        embedded: true,
        embeddedWidth: _kEmbeddedStack.width,
        beaconState: _authorBeaconState(),
        threadsState: threads,
        onRequestThreadRoute: (threadId, _) => routedThreadId = threadId,
      );

      expect(find.byType(ThreadDetail), findsNothing);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.requestThread(semantic.id))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(routedThreadId, semantic.id);
    });

    testWidgets('above pane threshold keeps split local across tabs', (
      tester,
    ) async {
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          return;
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);

      final semantic = _item(id: 'embedded-split');
      final threads = _threadsState(
        threads: [_generalThread(), _semanticThread(item: semantic)],
      );
      await _pumpHarness(
        tester,
        size: const Size(900, 900),
        embedded: true,
        embeddedWidth: 800,
        beaconState: _authorBeaconState(),
        threadsState: threads,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.requestThread(semantic.id))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ThreadDetail), findsOneWidget);

      await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabLog)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ThreadDetail), findsOneWidget);
    });
  });
}
