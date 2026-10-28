import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_status_sync.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../inbox/author_invite_test_support.dart'
    show registerEmptyAuthorInvitesGetIt, unregisterEmptyAuthorInvitesGetIt;
import '../beacon_plan/beacon_plan_test_support.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../../support/people_tags_widget_harness.dart';

const kBeaconViewHarnessBeaconId = 'b-view-harness';
const kBeaconViewHarnessAuthorId = 'author-harness';
final kBeaconViewHarnessNow = DateTime.utc(2026, 8, 14, 12);
final kBeaconViewHarnessSeenAt = DateTime.utc(2026, 8, 14, 10);
const kBeaconViewHarnessCompact = Size(390, 844);
const kBeaconViewHarnessExpanded = Size(1280, 900);

/// A Request plan with one untimed step: the Plan tab shows (#546).
const kBeaconViewHarnessOneStepPlan = BeaconPlan(
  beaconId: kBeaconViewHarnessBeaconId,
  editable: true,
  tickable: true,
  steps: [PlanStep(id: 'PS-harness-1', index: 1, title: 'Harness step')],
);

class BeaconViewHarnessRouter extends Mock implements RootStackRouter {
  int pushCount = 0;
  int popCount = 0;
  int maybePopCalls = 0;
  final List<String> replacedPaths = [];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    return null;
  }

  @override
  Future<T?> replacePath<T extends Object?>(
    String path, {
    bool includePrefixMatches = true,
    OnNavigationFailure? onFailure,
  }) async {
    replacedPaths.add(path);
    return null;
  }

  // BeaconViewScreen rewrites its URL in place via the root router.
  @override
  RootStackRouter get root => this;

  @override
  Future<void> navigatePath(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) async {
    replacedPaths.add(path);
  }

  @override
  void pop<T extends Object?>([T? result]) {
    popCount++;
  }

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    maybePopCalls++;
    return true;
  }

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

class BeaconViewHarness {
  BeaconViewHarness({
    required this.router,
    required this.threadsCubit,
    required this.host,
    required this.recorder,
    required this.mediaKey,
  });

  final BeaconViewHarnessRouter router;
  final ThreadsCubit threadsCubit;
  final ThreadHostCubit host;
  final BeaconViewRoomCubitRecorder recorder;
  final GlobalKey<BeaconViewResizableMediaQueryState> mediaKey;
}

class BeaconViewRoomCubitRecorder {
  final List<BeaconViewRecordingRoomCubit> created = [];

  BeaconViewRecordingRoomCubit call({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
  }) {
    final cubit = BeaconViewRecordingRoomCubit(
      beaconId: beaconId,
      threadItemId: threadItemId,
    );
    created.add(cubit);
    return cubit;
  }
}

class BeaconViewRecordingRoomCubit extends Mock implements RoomCubit {
  BeaconViewRecordingRoomCubit({
    required String beaconId,
    String? threadItemId,
  }) : closeCompleter = Completer<void>(),
       _state = RoomState(
         beaconId: beaconId,
         threadItemId: threadItemId,
         firstLoadDone: true,
       );

  final RoomState _state;
  final Completer<void> closeCompleter;
  int closeCallCount = 0;
  bool _isClosed = false;
  String? lastScrollMessageId;
  int prepareThreadScrollCalls = 0;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream.value(_state);

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> close() async {
    closeCallCount++;
    if (!closeCompleter.isCompleted) {
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
    prepareThreadScrollCalls++;
    lastScrollMessageId = messageId;
  }
}

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepository implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HarnessProfileCubit extends Mock implements ProfileCubit {
  _HarnessProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _HarnessBeaconViewCubit extends Mock implements BeaconViewCubit {
  _HarnessBeaconViewCubit(this._state) {
    _controller = StreamController<BeaconViewState>.broadcast();
    _controller.add(_state);
  }

  BeaconViewState _state;
  late final StreamController<BeaconViewState> _controller;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => _controller.stream;

  @override
  String get beaconId => _state.beacon.id;

  @override
  Profile get author => _state.beacon.author;

  @override
  bool get isAdmissionBlocked => _state.isRoomAdmissionBlocked;

  @override
  bool get coordinationDeniesAdmission => false;

  @override
  RoomCapabilities get capabilities => const RoomCapabilities.request();

  @override
  Stream<void> get changes => stream.map((_) {});

  @override
  Future<void> reportPeopleSurfaceViewed() async {}

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class _HarnessThreadsCubit extends Cubit<ThreadsState> implements ThreadsCubit {
  _HarnessThreadsCubit(super.initial);

  void emitState(ThreadsState value) => emit(value);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

class BeaconViewResizableMediaQuery extends StatefulWidget {
  const BeaconViewResizableMediaQuery({
    required this.child,
    required this.size,
    super.key,
  });

  final Widget child;
  final Size size;

  @override
  State<BeaconViewResizableMediaQuery> createState() =>
      BeaconViewResizableMediaQueryState();
}

class BeaconViewResizableMediaQueryState
    extends State<BeaconViewResizableMediaQuery> {
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

BeaconViewState beaconViewHarnessAuthorState({
  String beaconId = kBeaconViewHarnessBeaconId,
  String authorId = kBeaconViewHarnessAuthorId,
}) => BeaconViewState(
  beacon: Beacon(
    id: beaconId,
    title: 'Harness request',
    author: Profile(id: authorId, displayName: 'Author'),
    createdAt: kBeaconViewHarnessNow,
    updatedAt: kBeaconViewHarnessNow,
  ),
  myProfile: Profile(id: authorId, displayName: 'Author'),
  firstLoadDone: true,
  beaconContentLoaded: true,
  roomParticipantsLoaded: true,
  roomParticipants: [
    BeaconParticipant(
      id: 'p-author',
      beaconId: beaconId,
      userId: authorId,
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: kBeaconViewHarnessNow,
      updatedAt: kBeaconViewHarnessNow,
    ),
  ],
);

ThreadsState beaconViewHarnessThreadsState({
  List<RequestThread>? threads,
  String authorId = kBeaconViewHarnessAuthorId,
}) => ThreadsState(
  threads:
      threads ??
      [
        RequestThread(
          threadId: RequestThread.generalId,
          kind: RequestThreadKind.general,
          unreadCount: 0,
          lastSeenAt: kBeaconViewHarnessSeenAt,
        ),
      ],
  resolvedUnreadByThreadId: const {},
  myUserId: authorId,
  status: const StateIsSuccess(),
);

ThreadHostCubit beaconViewHarnessHost({
  BeaconViewRoomCubitRecorder? recorder,
  String beaconId = kBeaconViewHarnessBeaconId,
}) {
  final factoryRecorder = recorder ?? BeaconViewRoomCubitRecorder();
  return ThreadHostCubit(
    beaconId: beaconId,
    roomCubitFactory:
        ({
          required beaconId,
          threadItemId,
          initialUnreadAnchorAt,
          RoomCapabilities? capabilities,
        }) => factoryRecorder.call(
          beaconId: beaconId,
          threadItemId: threadItemId,
          initialUnreadAnchorAt: initialUnreadAnchorAt,
        ),
  );
}

Future<void> registerBeaconViewHarnessGetIt({
  Profile? profile,
  FakeBeaconThreadsRepository? roomRepo,
}) async {
  final getIt = GetIt.I;
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
    _HarnessProfileCubit(
      profile ?? Profile(id: kBeaconViewHarnessAuthorId, displayName: 'Author'),
    ),
  );
  if (getIt.isRegistered<BeaconThreadsCase>()) {
    await getIt.unregister<BeaconThreadsCase>();
  }
  getIt.registerSingleton<BeaconThreadsCase>(
    roomCubitMakeCase(
      roomRepo ??
          FakeBeaconThreadsRepository(
            userId: profile?.id ?? kBeaconViewHarnessAuthorId,
          ),
    ),
  );
  if (getIt.isRegistered<UiEffectPort>()) {
    await getIt.unregister<UiEffectPort>();
  }
  getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
  registerEmptyAuthorInvitesGetIt();
  // The Request route's host provides a PlanCubit (#220); an empty plan
  // keeps every plan row hidden.
  if (getIt.isRegistered<BeaconPlanCase>()) {
    await getIt.unregister<BeaconPlanCase>();
  }
  getIt.registerSingleton<BeaconPlanCase>(
    planCaseFor(FakeBeaconPlanRepository(const BeaconPlan(beaconId: ''))),
  );
}

Future<void> unregisterBeaconViewHarnessGetIt() async {
  final getIt = GetIt.I;
  if (getIt.isRegistered<BeaconPlanCase>()) {
    await getIt.unregister<BeaconPlanCase>();
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
  unregisterEmptyAuthorInvitesGetIt();
}

Future<BeaconViewHarness> pumpBeaconViewHarness(
  WidgetTester tester, {
  required Size size,
  required BeaconViewState beaconState,
  required ThreadsState threadsState,
  BeaconViewHarnessRouter? router,
  ThreadHostCubit? host,
  BeaconViewRoomCubitRecorder? recorder,
  String? viewTab,
  String? threadId,
  String? messageId,
  ThreadsCubit? threadsCubit,
  BeaconViewCubit? beaconViewCubit,
  Locale locale = const Locale('en'),
  // Runs after the harness registered its GetIt fakes, before the pump: a
  // test swaps one of them for its own.
  FutureOr<void> Function()? afterGetItRegistered,
  // The Request plan (#220) the host's PlanCubit serves; null: no PlanCubit
  // (and so no Plan tab, #546). See [kBeaconViewHarnessOneStepPlan].
  BeaconPlan? plan,
  // Mounts the status sync `BeaconViewScope` runs in the app (#415, #619):
  // the host, and so the room, learns the Request's status and author once
  // [beaconState] has loaded. False leaves the host unsynced.
  bool syncBeaconStatus = true,
}) async {
  final harnessRecorder = recorder ?? BeaconViewRoomCubitRecorder();
  final harnessHost = host ?? beaconViewHarnessHost(recorder: harnessRecorder);
  final harnessRouter = router ?? BeaconViewHarnessRouter();
  final beaconCubit = beaconViewCubit ?? _HarnessBeaconViewCubit(beaconState);
  final harnessThreadsCubit =
      threadsCubit ??
      _HarnessThreadsCubit(
        threadsState.copyWith(status: const StateIsLoading()),
      );
  final mediaKey = GlobalKey<BeaconViewResizableMediaQueryState>();

  await registerBeaconViewHarnessGetIt(profile: beaconState.myProfile);
  await afterGetItRegistered?.call();

  PlanCubit? planCubit;
  if (plan != null) {
    final cubit = planCubit = PlanCubit(
      beaconId: beaconState.beacon.id,
      viewerId: beaconState.myProfile.id,
      planCase: planCaseFor(FakeBeaconPlanRepository(plan)),
    );
    await tester.runAsync(cubit.load);
    addTearDown(() => tester.runAsync(cubit.close));
  }

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final screen = BeaconViewScreen(
    id: beaconState.beacon.id,
    viewTab: viewTab,
    threadId: threadId,
    messageId: messageId,
  );

  await tester.pumpPeopleTagsWidget(
    StackRouterScope(
      controller: harnessRouter,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: BeaconViewResizableMediaQuery(
          key: mediaKey,
          size: size,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              BlocProvider<BeaconViewCubit>.value(value: beaconCubit),
              BlocProvider<ThreadsCubit>.value(value: harnessThreadsCubit),
              BlocProvider<ThreadHostCubit>.value(value: harnessHost),
              if (planCubit != null)
                BlocProvider<PlanCubit>.value(value: planCubit),
              BlocProvider<BeaconHierarchyCubit>(
                create: (_) => BeaconHierarchyCubit(
                  beaconId: beaconState.beacon.id,
                  hierarchyCase: buildBeaconHierarchyCaseForTest(
                    FakeBeaconHierarchyRepositoryPort(
                      capabilities: const BeaconHierarchyCapabilities(
                        canListChildren: false,
                        canCreateChild: false,
                      ),
                    ),
                    createCase: BeaconCreateCase(
                      _NoopBeaconWritePort(),
                      _NoopImageRepository(),
                    ),
                    beacons: _NoopBeaconWritePort(),
                    commandStore: InMemoryBeaconChildCommandStore(),
                  ),
                ),
              ),
              BlocProvider<ProfileCubit>.value(
                value: _HarnessProfileCubit(beaconState.myProfile),
              ),
            ],
            child: syncBeaconStatus
                ? BeaconStatusSync(child: Scaffold(body: screen))
                : Scaffold(body: screen),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (harnessThreadsCubit is _HarnessThreadsCubit) {
    harnessThreadsCubit.emitState(threadsState);
  } else {
    harnessThreadsCubit.emit(threadsState);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  return BeaconViewHarness(
    router: harnessRouter,
    threadsCubit: harnessThreadsCubit,
    host: harnessHost,
    recorder: harnessRecorder,
    mediaKey: mediaKey,
  );
}

Widget buildBeaconViewHarnessWidget({
  required BeaconViewState beaconState,
  required ThreadsState threadsState,
  String? viewTab,
  String? threadId,
  String? messageId,
  String? planPage,
  ThreadsCubit? threadsCubit,
  ThreadHostCubit? host,
  BeaconViewRoomCubitRecorder? recorder,
  // Kept by the caller across rebuilds (a route rebuilding the screen).
  PlanCubit? planCubit,
  BeaconHierarchyCubit? hierarchyCubit,
}) {
  final harnessRecorder = recorder ?? BeaconViewRoomCubitRecorder();
  final harnessHost = host ?? beaconViewHarnessHost(recorder: harnessRecorder);
  final beaconCubit = _HarnessBeaconViewCubit(beaconState);
  final harnessThreadsCubit =
      threadsCubit ??
      _HarnessThreadsCubit(
        threadsState.copyWith(status: const StateIsLoading()),
      );

  return MultiBlocProvider(
    providers: [
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      BlocProvider<BeaconViewCubit>.value(value: beaconCubit),
      BlocProvider<ThreadsCubit>.value(value: harnessThreadsCubit),
      BlocProvider<ThreadHostCubit>.value(value: harnessHost),
      if (planCubit != null) BlocProvider<PlanCubit>.value(value: planCubit),
      if (hierarchyCubit != null)
        BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit)
      else
        BlocProvider<BeaconHierarchyCubit>(
          create: (_) => BeaconHierarchyCubit(
            beaconId: beaconState.beacon.id,
            hierarchyCase: buildBeaconHierarchyCaseForTest(
              FakeBeaconHierarchyRepositoryPort(
                capabilities: const BeaconHierarchyCapabilities(
                  canListChildren: false,
                  canCreateChild: false,
                ),
              ),
              createCase: BeaconCreateCase(
                _NoopBeaconWritePort(),
                _NoopImageRepository(),
              ),
              beacons: _NoopBeaconWritePort(),
              commandStore: InMemoryBeaconChildCommandStore(),
            ),
          ),
        ),
      BlocProvider<ProfileCubit>.value(
        value: _HarnessProfileCubit(beaconState.myProfile),
      ),
    ],
    child: Scaffold(
      body: BeaconViewScreen(
        id: beaconState.beacon.id,
        viewTab: viewTab,
        threadId: threadId,
        messageId: messageId,
        planPage: planPage,
      ),
    ),
  );
}

Future<void> resizeBeaconViewHarness(
  WidgetTester tester,
  BeaconViewHarness harness,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  harness.mediaKey.currentState!.resize(size);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> tapBeaconChatTabAndWaitForRoom(WidgetTester tester) async {
  await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabRoom)));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(ThreadDetail).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('ThreadDetail did not appear after selecting Chat');
}

PopScope beaconViewPopScope(WidgetTester tester) => tester.widget<PopScope>(
  find.byWidgetPredicate((widget) => widget is PopScope),
);
