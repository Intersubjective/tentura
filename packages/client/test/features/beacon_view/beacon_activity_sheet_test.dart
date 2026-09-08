import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_activity_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_surface_tabs.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fake_coordination_item_case.dart';
import '../beacon_threads/room_cubit_fakes.dart';

const _kBeaconId = 'b-activity-sheet';
const _kAuthorId = 'author-sheet';
const _kHelperId = 'helper-sheet';
final _kNow = DateTime.utc(2026, 8, 14, 12);

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HarnessBeaconViewCubit extends Mock implements BeaconViewCubit {
  _HarnessBeaconViewCubit(this._state) {
    _controller = StreamController<BeaconViewState>.broadcast();
    _controller.add(_state);
  }

  BeaconViewState _state;
  late final StreamController<BeaconViewState> _controller;

  void emitState(BeaconViewState value) {
    _state = value;
    _controller.add(_state);
  }

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => _controller.stream;

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

BeaconViewState _authorBeaconState({
  List<BeaconActivityEvent> roomActivityEvents = const [],
}) =>
    BeaconViewState(
      beacon: Beacon(
        id: _kBeaconId,
        title: 'Activity sheet beacon',
        author: const Profile(id: _kAuthorId, displayName: 'Author'),
        createdAt: _kNow,
        updatedAt: _kNow,
      ),
      myProfile: const Profile(id: _kAuthorId, displayName: 'Author'),
      beaconContentLoaded: true,
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
        BeaconParticipant(
          id: 'p-helper',
          beaconId: _kBeaconId,
          userId: _kHelperId,
          role: 0,
          status: 0,
          roomAccess: RoomAccessBits.admitted,
          createdAt: _kNow,
          updatedAt: _kNow,
        ),
      ],
      roomActivityEvents: roomActivityEvents,
    );

BeaconActivityEvent _coordinationEvent({
  required CoordinationItemKind kind,
  required String itemId,
  CoordinationItemEventKind eventKind = CoordinationItemEventKind.created,
  String? sourceMessageId,
  String? actorId,
  String? targetUserId,
}) =>
    BeaconActivityEvent(
      id: 'ev-$itemId-${eventKind.value}',
      beaconId: _kBeaconId,
      visibility: BeaconActivityEventVisibilityBits.room,
      type: kind.value * 100 + eventKind.value,
      createdAt: _kNow,
      coordinationItemId: itemId,
      sourceMessageId: sourceMessageId,
      actorId: actorId,
      targetUserId: targetUserId,
    );

BeaconActivityEvent _peopleFocusEvent({required String userId}) =>
    BeaconActivityEvent(
      id: 'ev-people-$userId',
      beaconId: _kBeaconId,
      visibility: BeaconActivityEventVisibilityBits.room,
      type: BeaconActivityEventTypeBits.factPinned,
      createdAt: _kNow,
      actorId: userId,
    );

List<BeaconActivityEvent> _manyCoordinationEvents(int count) => List.generate(
  count,
  (index) => _coordinationEvent(
    kind: CoordinationItemKind.ask,
    itemId: 'ask-$index',
    eventKind: CoordinationItemEventKind.created,
  ),
);

Widget _sheetHost({
  required BeaconViewCubit cubit,
  void Function(BeaconActivityEvent event)? onTap,
}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: TenturaResponsiveScope(
      child: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showBeaconActivitySheet(
              ctx,
              cubit: cubit,
              onTapCoordinationEvent: onTap ?? (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _HarnessThreadsCubit extends Cubit<ThreadsState> implements ThreadsCubit {
  _HarnessThreadsCubit(super.initial);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

class RecordingRoomCubit extends Mock implements RoomCubit {
  RecordingRoomCubit({required String beaconId})
    : closeCompleter = Completer<void>(),
      _state = RoomState(beaconId: beaconId);

  final RoomState _state;
  final Completer<void> closeCompleter;
  String? lastScrollMessageId;
  String? lastScrollCoordinationItemId;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream.value(_state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {
    if (!closeCompleter.isCompleted) {
      closeCompleter.complete();
    }
  }

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
    final cubit = RecordingRoomCubit(beaconId: beaconId);
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
  String? linkedMessageId,
}) =>
    CoordinationItem(
      id: id,
      beaconId: _kBeaconId,
      kind: kind,
      status: CoordinationItemStatus.open,
      creatorId: _kAuthorId,
      createdAt: _kNow,
      updatedAt: _kNow,
      published: true,
      targetPersonId: _kHelperId,
      linkedMessageId: linkedMessageId,
    );

RequestThread _generalThread() => RequestThread(
  threadId: RequestThread.generalId,
  kind: RequestThreadKind.general,
  lastSeenAt: _kNow,
);

ThreadsState _threadsState({required List<RequestThread> threads}) =>
    ThreadsState(
      threads: threads,
      resolvedUnreadByThreadId: const {},
      myUserId: _kAuthorId,
      status: const StateIsSuccess(),
    );

Future<void> _setupGetIt() async {
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
    _MockProfileCubit(const Profile(id: _kAuthorId, displayName: 'Author')),
  );
  if (getIt.isRegistered<BeaconThreadsCase>()) {
    await getIt.unregister<BeaconThreadsCase>();
  }
  getIt.registerSingleton<BeaconThreadsCase>(
    roomCubitMakeCase(FakeBeaconThreadsRepository(userId: _kAuthorId)),
  );
  if (getIt.isRegistered<UiEffectPort>()) {
    await getIt.unregister<UiEffectPort>();
  }
  getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
}

class _HarnessRouter extends Mock implements StackRouter {
  final List<String> replacedPaths = [];

  @override
  Future<T?> replacePath<T extends Object?>(
    String path, {
    bool includePrefixMatches = true,
    OnNavigationFailure? onFailure,
  }) async {
    replacedPaths.add(path);
    return null;
  }

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) =>
      false;
}

Future<void> _pumpBeaconViewScreen(
  WidgetTester tester, {
  required BeaconViewState beaconState,
  required ThreadsState threadsState,
  required ThreadHostCubit host,
  String? viewTab,
}) async {
  await _setupGetIt();
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final beaconCubit = _HarnessBeaconViewCubit(beaconState);
  final threadsCubit = _HarnessThreadsCubit(
    threadsState.copyWith(status: const StateIsLoading()),
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
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              BlocProvider<BeaconViewCubit>.value(value: beaconCubit),
              BlocProvider<ThreadsCubit>.value(value: threadsCubit),
              BlocProvider<ThreadHostCubit>.value(value: host),
              BlocProvider<BeaconHierarchyCubit>(
                create: (_) => BeaconHierarchyCubit(
                  beaconId: _kBeaconId,
                  hierarchyCase: buildBeaconHierarchyCaseForTest(
                    FakeBeaconHierarchyRepositoryPort(
                      capabilities: const BeaconHierarchyCapabilities(
                        canListChildren: false,
                        canCreateChild: false,
                      ),
                    ),
                    createCase: BeaconCreateCase(
                      _NoopBeaconWritePort(),
                      ImageRepository(),
                    ),
                    beacons: _NoopBeaconWritePort(),
                    commandStore: InMemoryBeaconChildCommandStore(),
                  ),
                ),
              ),
              BlocProvider<ProfileCubit>.value(
                value: _MockProfileCubit(beaconState.myProfile),
              ),
            ],
            child: Scaffold(
              body: BeaconViewScreen(id: _kBeaconId, viewTab: viewTab),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  threadsCubit.emit(threadsState);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _openActivityFromOverflow(WidgetTester tester) async {
  final l10n = await L10n.delegate.load(const Locale('en'));
  await tester.tap(find.byKey(TestIds.key(TestIds.beaconOverflowMenu)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.labelBeaconTabLog).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('long Activity history scrolls inside the sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = _HarnessBeaconViewCubit(
      _authorBeaconState(roomActivityEvents: _manyCoordinationEvents(40)),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_sheetHost(cubit: cubit));
    await _openSheet(tester);

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.labelBeaconTabLog), findsOneWidget);

    final scrollable = find.byType(Scrollable).last;
    expect(scrollable, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pump();
    expect(find.byType(BeaconActivityList), findsOneWidget);
  });

  testWidgets('room activity arriving while the sheet is open updates the list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = _HarnessBeaconViewCubit(_authorBeaconState());
    addTearDown(cubit.close);

    await tester.pumpWidget(_sheetHost(cubit: cubit));
    await _openSheet(tester);

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconNoActivityYetShort), findsOneWidget);

    cubit.emitState(
      _authorBeaconState(
        roomActivityEvents: [
          _coordinationEvent(kind: CoordinationItemKind.ask, itemId: 'ask-live'),
        ],
      ),
    );
    await tester.pump();

    expect(find.text(l10n.coordinationSemanticAskOpened), findsOneWidget);
    expect(find.text(l10n.beaconNoActivityYetShort), findsNothing);
  });

  testWidgets('log row tap closes the sheet before invoking the callback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tapped = <BeaconActivityEvent>[];
    final event = _coordinationEvent(kind: CoordinationItemKind.ask, itemId: 'a1');
    final cubit = _HarnessBeaconViewCubit(
      _authorBeaconState(roomActivityEvents: [event]),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _sheetHost(
        cubit: cubit,
        onTap: tapped.add,
      ),
    );
    await _openSheet(tester);

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.labelBeaconTabLog), findsOneWidget);

    await tester.tap(find.text(l10n.coordinationSemanticAskOpened));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.labelBeaconTabLog), findsNothing);
    expect(tapped, [event]);
  });

  testWidgets('overflow menu exposes Activity and opens the sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = _HarnessBeaconViewCubit(_authorBeaconState());
    addTearDown(cubit.close);
    final beacon = cubit.state.beacon;

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: BeaconOverflowMenu(
                  beacon: beacon,
                  onActivityLog: () => showBeaconActivitySheet(
                    context,
                    cubit: cubit,
                    onTapCoordinationEvent: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.tap(find.byKey(TestIds.key(TestIds.beaconOverflowMenu)));
    await tester.pumpAndSettle();
    expect(
      find.byKey(TestIds.key(TestIds.beaconOverflowActivity)),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.labelBeaconTabLog).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.labelBeaconTabLog), findsOneWidget);
  });

  group('log-row focus after sheet closes', () {
    Future<void> pumpAndOpenSheet(
      WidgetTester tester, {
      required List<BeaconActivityEvent> events,
      required ThreadsState threads,
      required ThreadHostCubit host,
    }) async {
      await _pumpBeaconViewScreen(
        tester,
        beaconState: _authorBeaconState(roomActivityEvents: events),
        threadsState: threads,
        host: host,
      );
      await _openActivityFromOverflow(tester);
    }

    testWidgets('ask row selects Chat at General', (tester) async {
      const itemId = 'ask-focus';
      final host = _host();
      final threads = _threadsState(
        threads: [
          _generalThread(),
          RequestThread(
            threadId: itemId,
            kind: RequestThreadKind.ask,
            item: _item(id: itemId, kind: CoordinationItemKind.ask),
            lastSeenAt: _kNow,
          ),
        ],
      );
      await pumpAndOpenSheet(
        tester,
        events: [_coordinationEvent(kind: CoordinationItemKind.ask, itemId: itemId)],
        threads: threads,
        host: host,
      );

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.coordinationSemanticAskOpened));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tabs = tester.widget<BeaconSurfaceTabs>(find.byType(BeaconSurfaceTabs));
      expect(tabs.selectedSurface, BeaconSurface.room);
      expect(find.text(l10n.labelBeaconTabLog), findsNothing);
    });

    testWidgets('blocker row selects Chat at General', (tester) async {
      const itemId = 'blocker-focus';
      final host = _host();
      final threads = _threadsState(
        threads: [
          _generalThread(),
          RequestThread(
            threadId: itemId,
            kind: RequestThreadKind.blocker,
            item: _item(id: itemId, kind: CoordinationItemKind.blocker),
            lastSeenAt: _kNow,
          ),
        ],
      );
      await pumpAndOpenSheet(
        tester,
        events: [
          _coordinationEvent(
            kind: CoordinationItemKind.blocker,
            itemId: itemId,
          ),
        ],
        threads: threads,
        host: host,
      );

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.coordinationSemanticBlockerOpened));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tabs = tester.widget<BeaconSurfaceTabs>(find.byType(BeaconSurfaceTabs));
      expect(tabs.selectedSurface, BeaconSurface.room);
    });

    testWidgets('plan row scrolls Chat to source message and item', (tester) async {
      const planId = 'plan-focus';
      const messageId = 'msg-plan';
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final plan = _item(
        id: planId,
        kind: CoordinationItemKind.plan,
        linkedMessageId: messageId,
      );
      final threads = _threadsState(
        threads: [_generalThread(), RequestThread(
          threadId: planId,
          kind: RequestThreadKind.ask,
          item: plan,
          lastSeenAt: _kNow,
        )],
      );
      await pumpAndOpenSheet(
        tester,
        events: [
          _coordinationEvent(
            kind: CoordinationItemKind.plan,
            itemId: planId,
            sourceMessageId: messageId,
          ),
        ],
        threads: threads,
        host: host,
      );

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.coordinationSemanticPlanOpened).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(host.state.openThreadId, RequestThread.generalId);
      final roomCubit = recorder.created.last;
      expect(roomCubit.lastScrollMessageId, messageId);
      expect(roomCubit.lastScrollCoordinationItemId, planId);
      expect(find.text(l10n.labelBeaconTabLog), findsNothing);
    });

    testWidgets('non-coordination row selects People with focus user', (
      tester,
    ) async {
      final host = _host();
      final threads = _threadsState(threads: [_generalThread()]);
      await pumpAndOpenSheet(
        tester,
        events: [_peopleFocusEvent(userId: _kHelperId)],
        threads: threads,
        host: host,
      );

      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.beaconActivityFactPinned));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tabs = tester.widget<BeaconSurfaceTabs>(find.byType(BeaconSurfaceTabs));
      expect(tabs.selectedSurface, BeaconSurface.people);
      expect(find.text(l10n.labelBeaconTabLog), findsNothing);
    });
  });
}
