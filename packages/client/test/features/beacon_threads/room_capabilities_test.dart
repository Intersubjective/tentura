import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

/// Names of Request-only fetches that were attempted, in call order.
typedef _Calls = List<String>;

/// Repository whose Request-only room-state fetch records and (optionally)
/// throws.
class _RequestOnlyRoomRepository extends FakeBeaconThreadsRepository {
  _RequestOnlyRoomRepository({
    required super.userId,
    required this.calls,
    required this.throwing,
  });

  final _Calls calls;
  final bool throwing;

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    calls.add('roomState');
    if (throwing) throw StateError('fetchBeaconRoomState must not be called');
    return super.fetchBeaconRoomState(beaconId);
  }
}

/// Fact-card repository whose list records and (optionally) throws.
class _RequestOnlyFactCardRepository extends FakeBeaconFactCardRepository {
  _RequestOnlyFactCardRepository({required this.calls, required this.throwing});

  final _Calls calls;
  final bool throwing;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    calls.add('facts');
    if (throwing) throw StateError('fact card list must not be called');
    return const [];
  }

  @override
  Future<int> correct({
    required String beaconId,
    required String factCardId,
    required String newText,
    required int baseRevisionSeq,
    String? attachmentsJson,
  }) async => baseRevisionSeq + 1;
}

/// Use case whose plan / blocker / coordination-item fetches record and
/// (optionally) throw; room state and facts go through the repositories.
base class _RequestOnlyCase extends BeaconThreadsCase {
  _RequestOnlyCase(
    _RequestOnlyRoomRepository room,
    _RequestOnlyFactCardRepository facts,
    this.port,
    RealtimeSyncCase realtime, {
    required this.calls,
    required this.throwing,
  }) : super(
         room,
         facts,
         FakePollingRepository(),
         FakeBeaconRoomHintsRepository(),
         RoomReadWatermarkStore.testing(),
         realtime,
         env: const Env(),
         logger: Logger('test'),
       );

  final TestRealtimeSyncPort port;
  final _Calls calls;
  final bool throwing;

  T _hit<T>(String name, T value) {
    calls.add(name);
    if (throwing) throw StateError('$name must not be called');
    return value;
  }

  @override
  Future<CoordinationItem?> fetchCurrentCoordinationPlan(
    String beaconId,
  ) async => _hit<CoordinationItem?>('plan', null);

  @override
  Future<CoordinationItem?> fetchOpenCoordinationBlocker(
    String beaconId,
  ) async => _hit<CoordinationItem?>('blocker', null);

  @override
  Future<List<CoordinationItem>> fetchCoordinationItems(
    String beaconId,
  ) async => _hit('coordinationItems', const <CoordinationItem>[]);
}

class _Harness {
  _Harness({required bool throwing}) {
    final realtime = buildTestRealtimeSync();
    port = realtime.port;
    room = _RequestOnlyRoomRepository(
      userId: kRoomCubitFakeMyUserId,
      calls: calls,
      throwing: throwing,
    );
    facts = _RequestOnlyFactCardRepository(calls: calls, throwing: throwing);
    useCase = _RequestOnlyCase(
      room,
      facts,
      port,
      realtime.case_,
      calls: calls,
      throwing: throwing,
    );
  }

  final _Calls calls = [];
  late final TestRealtimeSyncPort port;
  late final _RequestOnlyRoomRepository room;
  late final _RequestOnlyFactCardRepository facts;
  late final _RequestOnlyCase useCase;

  RoomCubit cubit({RoomCapabilities? capabilities}) => RoomCubit(
    beaconId: kRoomCubitFakeBeaconId,
    beaconRoomCase: useCase,
    coordinationItemRoomSync: CoordinationItemRoomSync(),
    presenceRepository: roomCubitFakePresenceRepository(),
    effects: FakeUiEffectPort(),
    capabilities: capabilities ?? const RoomCapabilities.request(),
  );
}

/// Matches exactly one call of each name in [names], in any order.
Matcher _calledOnce(List<String> names) => unorderedEquals(names);

Future<void> _settle() => pumpEventQueue(times: 40);

const _requestOnly = ['roomState', 'plan', 'facts', 'blocker', 'coordinationItems'];

final _generalThread = RequestThread(
  threadId: RequestThread.generalId,
  kind: RequestThreadKind.general,
  lastSeenAt: DateTime.utc(2026),
);

void _registerRoomDependencies(_Harness h) {
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final getIt = GetIt.instance;
  getIt
    ..registerSingleton<BeaconThreadsCase>(h.useCase)
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(roomCubitFakePresenceRepository())
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort());
  addTearDown(() {
    getIt
      ..unregister<BeaconThreadsCase>()
      ..unregister<CoordinationItemRoomSync>()
      ..unregister<PresenceRepository>()
      ..unregister<UiEffectPort>();
  });
}

void main() {
  group('RoomCapabilities presets', () {
    test('request preset turns every flag on and pins the Now strip', () {
      const caps = RoomCapabilities.request();
      expect(caps.plan, isTrue);
      expect(caps.facts, isTrue);
      expect(caps.blocker, isTrue);
      expect(caps.coordinationItems, isTrue);
      expect(caps.childPromotion, isTrue);
      expect(caps.commitmentSheet, isTrue);
      expect(caps.closure, isTrue);
      expect(caps.pinnedStrip, RoomPinnedStrip.requestNow);
    });

    test('post preset turns every flag off and pins the root strip', () {
      const caps = RoomCapabilities.post();
      expect(caps.plan, isFalse);
      expect(caps.facts, isFalse);
      expect(caps.blocker, isFalse);
      expect(caps.coordinationItems, isFalse);
      expect(caps.childPromotion, isFalse);
      expect(caps.commitmentSheet, isFalse);
      expect(caps.closure, isFalse);
      expect(caps.pinnedStrip, RoomPinnedStrip.postRoot);
    });
  });

  group('RoomCubit with post capabilities', () {
    late _Harness h;
    late RoomCubit cubit;

    setUp(() async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      h = _Harness(throwing: true);
      cubit = h.cubit(capabilities: const RoomCapabilities.post());
      addTearDown(cubit.close);
      final loaded = await awaitRoomCubitLoad(cubit);
      expect(loaded.status, isA<StateIsSuccess>());
    });

    test('exposes the capabilities it was built with', () {
      expect(cubit.capabilities, const RoomCapabilities.post());
    });

    test('initial load makes no Request-only fetch', () {
      expect(h.calls, isEmpty);
    });

    test('reloadMessages makes no Request-only fetch', () async {
      await cubit.reloadMessages();
      expect(h.calls, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });

    test('realtime catch-up refresh makes no Request-only fetch', () async {
      h.port.emitCatchUp();
      await _settle();
      expect(h.calls, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });

    test('fact correction refresh makes no Request-only fetch', () async {
      await cubit.correctFact(
        factCardId: 'f1',
        newText: 'text',
        baseRevisionSeq: 1,
      );
      await _settle();
      expect(h.calls, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });

    test('message-delete invalidation refresh makes no Request-only fetch',
        () async {
      h.room.emitInvalidation(
        BeaconRoomEntityType.roomMessage,
        operation: RealtimeOperation.delete,
        messageId: 'gone',
      );
      await _settle();
      expect(h.calls, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });

    test('missing scroll target reload makes no Request-only fetch', () async {
      h.room.messages = [
        RoomMessage(
          id: 'm1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: 'other',
          body: 'hi',
          createdAt: DateTime.utc(2026),
        ),
      ];
      await cubit.reloadMessages();
      cubit.prepareThreadScroll(messageId: 'not-loaded');
      await _settle();
      expect(h.calls, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });

    test('sending with an upload (follow-up refresh) makes no Request-only '
        'fetch', () async {
      final sent = await cubit.sendMessage(
        body: 'hello',
        uploads: [roomCubitFakeUpload('a.bin')],
      );
      await _settle();
      expect(sent, isTrue);
      expect(h.calls, isEmpty);
    });

    for (final type in BeaconRoomEntityType.values) {
      test('$type invalidation refresh makes no Request-only fetch', () async {
        h.room.emitInvalidation(type);
        await _settle();
        expect(h.calls, isEmpty);
        expect(cubit.state.status, isA<StateIsSuccess>());
      });
    }
  });

  group('RoomCubit with request capabilities', () {
    late _Harness h;
    late RoomCubit cubit;

    setUp(() async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      h = _Harness(throwing: false);
      cubit = h.cubit();
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      await _settle();
      h.calls.clear();
    });

    test('defaults to request capabilities', () {
      expect(cubit.capabilities, const RoomCapabilities.request());
    });

    test('reloadMessages calls each Request-only fetch once', () async {
      await cubit.reloadMessages();
      expect(h.calls, _calledOnce(_requestOnly));
    });

    test('realtime catch-up calls each Request-only fetch once', () async {
      h.port.emitCatchUp();
      await _settle();
      expect(h.calls, _calledOnce(_requestOnly));
    });

    test('missing scroll target reload calls each Request-only fetch once',
        () async {
      h.room.messages = [
        RoomMessage(
          id: 'm1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: 'other',
          body: 'hi',
          createdAt: DateTime.utc(2026),
        ),
      ];
      await cubit.reloadMessages();
      h.calls.clear();

      cubit.prepareThreadScroll(messageId: 'not-loaded');
      await _settle();

      expect(h.calls, _calledOnce(_requestOnly));
    });

    for (final type in [
      BeaconRoomEntityType.participant,
      BeaconRoomEntityType.coordinationItem,
      BeaconRoomEntityType.helpOffer,
      BeaconRoomEntityType.activityEvent,
    ]) {
      test('$type invalidation calls each Request-only fetch once', () async {
        h.room.emitInvalidation(type);
        await _settle();
        expect(h.calls, _calledOnce(_requestOnly));
      });
    }

    for (final type in [
      BeaconRoomEntityType.roomMessage,
      BeaconRoomEntityType.roomReaction,
      BeaconRoomEntityType.roomPoll,
    ]) {
      test('$type invalidation refreshes messages only', () async {
        h.room.emitInvalidation(type);
        await _settle();
        expect(h.calls, isEmpty);
      });
    }

    test('fact invalidation fetches only the fact list, once', () async {
      h.room.emitInvalidation(BeaconRoomEntityType.factCard);
      await _settle();
      expect(h.calls, _calledOnce(['facts']));
    });

    test('fact correction fetches only the fact list, once', () async {
      await cubit.correctFact(
        factCardId: 'f1',
        newText: 'text',
        baseRevisionSeq: 1,
      );
      await _settle();
      expect(h.calls, _calledOnce(['facts']));
    });
  });

  group('RoomCubit initial load with request capabilities', () {
    test('calls every Request-only fetch', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final h = _Harness(throwing: false);
      final cubit = h.cubit();
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      expect(h.calls, _calledOnce(_requestOnly));
    });
  });

  group('ThreadHostCubit capabilities (production room factory)', () {
    test('builds a post-capability RoomCubit that skips Request-only fetches',
        () async {
      final h = _Harness(throwing: true);
      _registerRoomDependencies(h);
      final host = ThreadHostCubit(
        beaconId: kRoomCubitFakeBeaconId,
        capabilities: const RoomCapabilities.post(),
      );
      addTearDown(host.close);

      await host.ensureGeneral(_generalThread);
      final room = host.roomCubit!;
      await awaitRoomCubitLoad(room);

      expect(room.capabilities, const RoomCapabilities.post());
      expect(h.calls, isEmpty);
      expect(room.state.status, isA<StateIsSuccess>());
    });

    test('builds a request-capability RoomCubit by default', () async {
      final h = _Harness(throwing: false);
      _registerRoomDependencies(h);
      final host = ThreadHostCubit(beaconId: kRoomCubitFakeBeaconId);
      addTearDown(host.close);

      await host.ensureGeneral(_generalThread);
      final room = host.roomCubit!;
      await awaitRoomCubitLoad(room);

      expect(room.capabilities, const RoomCapabilities.request());
      expect(h.calls, _calledOnce(_requestOnly));
    });
  });
}
