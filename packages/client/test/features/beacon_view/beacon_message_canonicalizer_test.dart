import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_host_screen.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_navigation_scope.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_screen_harness.dart';

const _kBeaconId = 'b-message-canonicalizer';
const _kAuthorId = 'author-canonicalizer';
final _kNow = DateTime.utc(2026, 8, 14, 12);
final _kSeenAt = DateTime.utc(2026, 8, 14, 10);

class _CanonicalizerRouter extends Mock implements StackRouter {
  final List<PageRouteInfo<Object?>> replaced = [];

  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo<Object?> route, {
    OnNavigationFailure? onFailure,
  }) async {
    replaced.add(route);
    return null;
  }

  @override
  Future<T?> replacePath<T extends Object?>(
    String path, {
    bool includePrefixMatches = true,
    OnNavigationFailure? onFailure,
  }) async =>
      null;

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) =>
      false;
}

/// Host screen whose [build] is a placeholder so tests avoid [AutoRouter].
class _TestableBeaconViewHostScreen extends BeaconViewHostScreen {
  const _TestableBeaconViewHostScreen({
    required super.id,
    super.messageId,
    super.threadId,
    super.viewTab,
    super.key,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _MessageTargetRepository extends FakeBeaconThreadsRepository {
  _MessageTargetRepository({required super.userId});

  final Map<String, Future<RoomMessage?>> targetsByMessageId = {};
  final Map<String, Object?> errorsByMessageId = {};
  int fetchMessageTargetCalls = 0;

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async => [
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      unreadCount: 0,
      lastSeenAt: _kSeenAt,
    ),
  ];

  @override
  Future<RoomMessage?> fetchMessageTarget({
    required String beaconId,
    required String messageId,
  }) async {
    fetchMessageTargetCalls++;
    final error = errorsByMessageId[messageId];
    if (error != null) {
      if (error is Exception) throw error;
      if (error is Error) throw error;
      throw StateError(error.toString());
    }
    final pending = targetsByMessageId[messageId];
    if (pending != null) return pending;
    return RoomMessage(
      id: messageId,
      beaconId: beaconId,
      authorId: _kAuthorId,
      body: 'target',
      createdAt: _kNow,
      threadItemId: RequestThread.generalId,
    );
  }
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

Future<void> _setupGetIt(_MessageTargetRepository repo) async {
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
    _MockProfileCubit(const Profile(id: _kAuthorId, displayName: 'Author')),
  );
  if (getIt.isRegistered<BeaconThreadsCase>()) {
    await getIt.unregister<BeaconThreadsCase>();
  }
  getIt.registerSingleton<BeaconThreadsCase>(roomCubitMakeCase(repo));
  if (getIt.isRegistered<BeaconViewCase>()) {
    await getIt.unregister<BeaconViewCase>();
  }
  getIt.registerSingleton<BeaconViewCase>(buildTestBeaconViewCase());
  if (getIt.isRegistered<UiEffectPort>()) {
    await getIt.unregister<UiEffectPort>();
  }
  getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
}

Future<_CanonicalizerRouter> _pumpCanonicalizerHost(
  WidgetTester tester, {
  required _CanonicalizerRouter router,
  required _MessageTargetRepository repo,
  String? messageId,
  String? threadId,
  String? viewTab,
}) async {
  await _setupGetIt(repo);
  final host = _TestableBeaconViewHostScreen(
    key: ValueKey('canonicalizer-$messageId-$threadId'),
    id: _kBeaconId,
    messageId: messageId,
    threadId: threadId,
    viewTab: viewTab,
  );

  await tester.pumpWidget(
    _canonicalizerMaterial(
      router: router,
      child: (context) => host.wrappedRoute(context),
    ),
  );
  await tester.pump();
  return router;
}

Widget _canonicalizerMaterial({
  required _CanonicalizerRouter router,
  required Widget Function(BuildContext context) child,
}) {
  return StackRouterScope(
    controller: router,
    stateHash: 0,
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<ProfileCubit>.value(
        value: GetIt.I<ProfileCubit>(),
        child: Builder(builder: child),
      ),
    ),
  );
}

Future<void> _repumpCanonicalizerHost(
  WidgetTester tester, {
  required _CanonicalizerRouter router,
  String? messageId,
  String? threadId,
}) async {
  await tester.pumpWidget(
    _canonicalizerMaterial(
      router: router,
      child: (context) => _TestableBeaconViewHostScreen(
        key: ValueKey('canonicalizer-$messageId-$threadId'),
        id: _kBeaconId,
        messageId: messageId,
        threadId: threadId,
      ).wrappedRoute(context),
    ),
  );
  await tester.pump();
}

String? _messageIdFromReplace(PageRouteInfo<Object?> route) {
  if (route is! BeaconViewOperationalRoute) return null;
  return route.args?.messageId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    final getIt = GetIt.I;
    if (getIt.isRegistered<ProfileCubit>()) {
      await getIt.unregister<ProfileCubit>();
    }
    if (getIt.isRegistered<BeaconThreadsCase>()) {
      await getIt.unregister<BeaconThreadsCase>();
    }
    if (getIt.isRegistered<BeaconViewCase>()) {
      await getIt.unregister<BeaconViewCase>();
    }
    if (getIt.isRegistered<UiEffectPort>()) {
      await getIt.unregister<UiEffectPort>();
    }
  });

  group('?message= host canonicalizer (T9 / F3)', () {
    testWidgets('slow resolve for older message does not override newer target', (
      tester,
    ) async {
      final repo = _MessageTargetRepository(userId: _kAuthorId);
      final slowA = Completer<RoomMessage?>();
      final fastB = Completer<RoomMessage?>();
      repo.targetsByMessageId['M-A'] = slowA.future;
      repo.targetsByMessageId['M-B'] = fastB.future;

      final router = _CanonicalizerRouter();
      await _pumpCanonicalizerHost(
        tester,
        router: router,
        repo: repo,
        messageId: 'M-A',
      );
      await tester.pump();

      await _repumpCanonicalizerHost(
        tester,
        router: router,
        messageId: 'M-B',
      );

      fastB.complete(
        RoomMessage(
          id: 'M-B',
          beaconId: _kBeaconId,
          authorId: _kAuthorId,
          body: 'B',
          createdAt: _kNow,
          threadItemId: RequestThread.generalId,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      slowA.complete(
        RoomMessage(
          id: 'M-A',
          beaconId: _kBeaconId,
          authorId: _kAuthorId,
          body: 'A',
          createdAt: _kNow,
          threadItemId: RequestThread.generalId,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(router.replaced, isNotEmpty);
      expect(_messageIdFromReplace(router.replaced.last), 'M-B');
      expect(
        router.replaced.map(_messageIdFromReplace),
        isNot(contains('M-A')),
      );
    });

    testWidgets('failed resolve leaves message retryable on next attempt', (
      tester,
    ) async {
      final repo = _MessageTargetRepository(userId: _kAuthorId);
      repo.errorsByMessageId['M-retry'] = StateError('network');

      final router = _CanonicalizerRouter();
      await _pumpCanonicalizerHost(
        tester,
        router: router,
        repo: repo,
        messageId: 'M-retry',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(router.replaced, isEmpty);
      expect(repo.fetchMessageTargetCalls, 1);

      repo.errorsByMessageId.remove('M-retry');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _repumpCanonicalizerHost(
        tester,
        router: router,
        messageId: 'M-retry',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(repo.fetchMessageTargetCalls, greaterThan(1));
      expect(router.replaced, isNotEmpty);
      expect(_messageIdFromReplace(router.replaced.last), 'M-retry');
    });

    testWidgets('stale resolve after message cleared does not replace route', (
      tester,
    ) async {
      final repo = _MessageTargetRepository(userId: _kAuthorId);
      final slow = Completer<RoomMessage?>();
      repo.targetsByMessageId['M-stale'] = slow.future;

      final router = _CanonicalizerRouter();
      await _pumpCanonicalizerHost(
        tester,
        router: router,
        repo: repo,
        messageId: 'M-stale',
      );
      await tester.pump();

      await _repumpCanonicalizerHost(tester, router: router);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      slow.complete(
        RoomMessage(
          id: 'M-stale',
          beaconId: _kBeaconId,
          authorId: _kAuthorId,
          body: 'stale',
          createdAt: _kNow,
          threadItemId: RequestThread.generalId,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(router.replaced, isEmpty);
    });
  });

  group('message scroll hand-off on mounted General surface', () {
    testWidgets('new message target scrolls without remounting room', (
      tester,
    ) async {
      final threads = [
        ...beaconViewHarnessThreadsState().threads,
        RequestThread(
          threadId: 'coord-scroll',
          kind: RequestThreadKind.ask,
          unreadCount: 0,
          item: CoordinationItem(
            id: 'coord-scroll',
            beaconId: kBeaconViewHarnessBeaconId,
            kind: CoordinationItemKind.ask,
            status: CoordinationItemStatus.open,
            creatorId: kBeaconViewHarnessAuthorId,
            createdAt: kBeaconViewHarnessNow,
            updatedAt: kBeaconViewHarnessNow,
            published: true,
            targetPersonId: 'helper',
            title: 'Ask',
          ),
          lastSeenAt: kBeaconViewHarnessSeenAt,
        ),
      ];
      final recorder = BeaconViewRoomCubitRecorder();
      final host = beaconViewHarnessHost(recorder: recorder);

      await registerBeaconViewHarnessGetIt();
      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessExpanded,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(threads: threads),
        host: host,
        recorder: recorder,
      );

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ThreadDetail).evaluate().isNotEmpty &&
            recorder.created.isNotEmpty) {
          break;
        }
      }

      expect(recorder.created, hasLength(1));
      final room = recorder.created.single;
      expect(find.byType(ThreadDetail), findsOneWidget);

      final scope = tester.widget<BeaconRoomNavigationScope>(
        find.byType(BeaconRoomNavigationScope),
      );
      await scope.openGeneralAnchor(messageId: 'M-scroll');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(recorder.created, hasLength(1));
      expect(identical(recorder.created.single, room), isTrue);
      expect(room.closeCallCount, 0);
      expect(room.lastScrollMessageId, 'M-scroll');
      expect(room.prepareThreadScrollCalls, greaterThan(0));
    });
  });
}
