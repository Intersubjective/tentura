import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
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
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/coordination_item/ui/bloc/item_actions_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';

import 'fake_coordination_item_case.dart';
import 'room_cubit_fakes.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
const _kBeaconId = 'b-detail-test';
const _kMyId = 'viewer-1';
final _kSeenAt = DateTime.utc(2026, 8, 14, 10);

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

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  _MockBeaconViewCubit(this._state);

  final BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream.value(_state);
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
  bool _isClosed = false;

  /// When true, [close] waits until [closeCompleter] is completed externally.
  bool gateClose = false;

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
  void prepareThreadScroll({String? messageId, String? coordinationItemId}) {}
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

CoordinationItem _item(String id, {String title = 'Ask title preview'}) =>
    CoordinationItem(
      id: id,
      beaconId: _kBeaconId,
      kind: CoordinationItemKind.ask,
      status: CoordinationItemStatus.open,
      creatorId: 'creator',
      title: title,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      published: true,
    );

RequestThread _generalThread() => RequestThread(
  threadId: RequestThread.generalId,
  kind: RequestThreadKind.general,
  lastSeenAt: _kSeenAt,
);

RequestThread _semanticThread(String itemId) {
  final item = _item(itemId);
  return RequestThread(
    threadId: itemId,
    kind: RequestThreadKind.ask,
    lastSeenAt: _kSeenAt,
    item: item,
  );
}

BeaconViewState _beaconState() => BeaconViewState(
  myProfile: const Profile(id: _kMyId, displayName: 'Viewer'),
  beacon: Beacon(
    id: _kBeaconId,
    title: 'Request title',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    author: const Profile(id: 'author', displayName: 'Author'),
  ),
  status: const StateIsSuccess(),
);

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

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _kMyId, displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _PopTrackingStackRouter extends Mock implements StackRouter {
  int popCount = 0;

  @override
  void pop<T extends Object?>([T? result]) {
    popCount++;
  }
}

Future<void> _pumpWithRouter(
  WidgetTester tester, {
  required StackRouter router,
  required Widget child,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(child: child),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntilThreadDetailLoaded(
  WidgetTester tester, {
  int maxFrames = 60,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(BackButton).evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _pumpThreadDetail(
  WidgetTester tester, {
  required ThreadHostCubit host,
  required ThreadsState threadsState,
  required BeaconViewState beaconState,
  required String threadId,
  required StackRouter router,
  Size size = const Size(390, 844),
}) async {
  await _pumpWithRouter(
    tester,
    router: router,
    size: size,
    child: MultiBlocProvider(
      providers: [
        BlocProvider<ThreadsCubit>.value(
          value: _MockThreadsCubit(threadsState),
        ),
        BlocProvider<ThreadHostCubit>.value(value: host),
        BlocProvider<BeaconViewCubit>.value(
          value: _MockBeaconViewCubit(beaconState),
        ),
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
      ],
      child: ThreadDetailScreen(
        beaconId: _kBeaconId,
        threadId: threadId,
      ),
    ),
  );
  await _pumpUntilThreadDetailLoaded(tester);
}

Future<void> _setupGetIt() async {
  final getIt = GetIt.I;
  await getIt.reset();
  getIt.registerSingleton<ProfileCubit>(_MockProfileCubit());
  getIt.registerSingleton<ImageRepository>(ImageRepository());
  getIt.registerSingleton<ClipboardImageRepository>(
    ClipboardImageRepository(),
  );
  getIt.registerSingleton<CoordinationItemCase>(
    const FakeCoordinationItemCaseForRoom(),
  );
  getIt.registerSingleton<BeaconThreadsCase>(
    roomCubitMakeCase(FakeBeaconThreadsRepository(userId: _kMyId)),
  );
  getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
}

void main() {
  setUp(() async {
    await _setupGetIt();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('ThreadDetail widget', () {
    testWidgets('general thread renders body without semantic header', (
      tester,
    ) async {
      final host = _host();
      await host.select(_generalThread());
      final thread = _generalThread();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: BlocProvider<ThreadHostCubit>.value(
                        value: host,
                        child: ThreadDetail(thread: thread),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(BeaconRoomBody), findsOneWidget);
    });

    testWidgets('semantic thread renders body without pinned header', (
      tester,
    ) async {
      final host = _host();
      final thread = _semanticThread('ask-1');
      await host.select(thread);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final profileCubit = _MockProfileCubit();

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: MultiBlocProvider(
                        providers: [
                          BlocProvider<ThreadHostCubit>.value(value: host),
                          BlocProvider<ProfileCubit>.value(value: profileCubit),
                          BlocProvider(
                            create: (_) => ItemActionsCubit(item: thread.item!),
                          ),
                        ],
                        child: ThreadDetail(thread: thread),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(BeaconRoomBody), findsOneWidget);
    });
  });

  group('ThreadDetailScreen', () {
    testWidgets('shows request title for General and composer unconditionally', (
      tester,
    ) async {
      final host = _host();
      final threadsState = ThreadsState(
        threads: [_generalThread()],
        myUserId: _kMyId,
        status: const StateIsSuccess(),
      );
      final router = _PopTrackingStackRouter();

      await _pumpThreadDetail(
        tester,
        host: host,
        threadsState: threadsState,
        beaconState: _beaconState(),
        threadId: RequestThread.generalId,
        router: router,
      );

      expect(find.byType(ThreadDetailGeneralTitle), findsOneWidget);
      expect(find.text('Request title'), findsOneWidget);
      expect(find.byType(BeaconInvolvedPeopleFacePile), findsOneWidget);
      expect(
        find.byKey(TestIds.key(TestIds.roomMessageInput)),
        findsOneWidget,
      );

      await tester.tap(find.text('Request title'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ask thread AppBar title and overflow find ItemActionsCubit', (
      tester,
    ) async {
      final host = _host();
      final ask = _semanticThread('ask-1');
      final threadsState = ThreadsState(
        threads: [ask],
        myUserId: _kMyId,
        status: const StateIsSuccess(),
      );
      final router = _PopTrackingStackRouter();

      await _pumpThreadDetail(
        tester,
        host: host,
        threadsState: threadsState,
        beaconState: _beaconState(),
        threadId: ask.threadId,
        router: router,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ThreadDetailTitle), findsOneWidget);
      expect(find.byType(ThreadDetailOverflowAction), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('Ask title preview'), findsOneWidget);
      expect(find.text('Ask'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('close awaits host clear before route pop completes', (
      tester,
    ) async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final threadsState = ThreadsState(
        threads: [_generalThread()],
        myUserId: _kMyId,
        status: const StateIsSuccess(),
      );
      final router = _PopTrackingStackRouter();

      await _pumpThreadDetail(
        tester,
        host: host,
        threadsState: threadsState,
        beaconState: _beaconState(),
        threadId: RequestThread.generalId,
        router: router,
      );

      expect(recorder.created, hasLength(1));
      final owned = recorder.created.single;
      owned.gateClose = true;

      await tester.tap(find.byType(BackButton));
      await tester.pump();

      expect(router.popCount, 0);
      expect(owned.closeCallCount, 1);

      owned.closeCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(router.popCount, 1);
    });
  });
}
