import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/block/data/repository/block_repository.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';

import '../my_work/my_work_test_support.dart' as work;
import 'inbox_case_test.dart' show FakeInboxRepository;

void main() {
  group('Inbox refresh streams release every source after the last listener', () {
    for (final channel in [
      'local mutations',
      'forward commands',
      'desk changes',
      'catch-ups',
    ]) {
      test(
        '$channel delivers every source to remaining listeners and allows upstream shutdown',
        () {
          fakeAsync((async) {
            final harness = _Harness();
            final sources = harness.sourcesFor(channel);
            final stream = harness.streamFor(channel);
            final expected =
                channel == 'local mutations' || channel == 'catch-ups'
                ? null
                : 'request-a';
            final firstEvents = <Object?>[];
            final secondEvents = <Object?>[];
            final first = stream.listen(firstEvents.add);
            final second = stream.listen(secondEvents.add);
            Map<String, bool>? retained;
            try {
              for (final source in sources) {
                source.emit();
              }
              async.flushMicrotasks();
              expect(
                firstEvents,
                List<Object?>.filled(sources.length, expected),
              );
              expect(secondEvents, firstEvents);

              unawaited(first.cancel());
              async.flushMicrotasks();
              expect(
                {for (final source in sources) source.name: source.hasListener},
                {for (final source in sources) source.name: true},
                reason:
                    'The remaining observer still needs every upstream source.',
              );
              for (final source in sources) {
                source.emit();
              }
              async.flushMicrotasks();
              expect(
                firstEvents,
                List<Object?>.filled(sources.length, expected),
              );
              expect(
                secondEvents,
                List<Object?>.filled(sources.length * 2, expected),
              );

              unawaited(second.cancel());
              async.flushMicrotasks();
              retained = {
                for (final source in sources) source.name: source.hasListener,
              };
            } finally {
              unawaited(first.cancel());
              unawaited(second.cancel());
              // Await each injected controller's close in this fake-async zone.
              // Each await stops after one simulated second, even if a retained
              // or paused subscription prevents the controller from shutting down.
              final closed = <String, bool>{};
              final closeErrors = <String, Object>{};
              Future<void> closeSource(_Source<dynamic> source) async {
                try {
                  await source.close().timeout(const Duration(seconds: 1));
                  closed[source.name] = true;
                } on Object catch (error) {
                  closeErrors[source.name] = error;
                }
              }

              final shutdown = Future.wait(harness.allSources.map(closeSource));
              var shutdownCompleted = false;
              unawaited(shutdown.then((_) => shutdownCompleted = true));
              async
                ..flushMicrotasks()
                ..elapse(const Duration(milliseconds: 1100))
                ..flushMicrotasks();
              expect(
                closeErrors,
                isEmpty,
                reason:
                    'Every upstream close() must finish within one simulated second.',
              );
              expect(shutdownCompleted, isTrue);
              expect(closed, {
                for (final source in harness.allSources) source.name: true,
              });
            }
            expect(
              retained,
              {for (final source in sources) source.name: false},
              reason:
                  'After the final observer cancels, no merge input may retain its subscription.',
            );
          });
        },
      );
    }
  });
}

class _Source<T> {
  _Source(this.name, this.event);
  final String name;
  final T event;
  final _controller = StreamController<T>.broadcast();
  Stream<T> get stream => _controller.stream;
  bool get hasListener => _controller.hasListener;
  void emit() => _controller.add(event);
  Future<void> close() => _controller.close();
}

class _Harness {
  final mutations = _Source<void>('inbox local mutations', null);
  final bookkeeping = _Source<void>('bookkeeping refresh', null);
  final blocks = _Source<RepositoryEvent<BlockIntent>>(
    'block changes',
    const RepositoryEventCreate(
      BlockIntent(blocked: Profile(id: 'blocked-user')),
    ),
  );
  final commands = _Source<String>('forward commands', 'request-a');
  final room = _Source<BeaconRoomInvalidation>(
    'beacon-thread changes',
    const BeaconRoomInvalidation(
      beaconId: 'request-a',
      entityType: BeaconRoomEntityType.roomMessage,
    ),
  );
  final forwards = _Source<String>('forward changes', 'request-a');
  final offers = _Source<HelpOfferEvent>(
    'help-offer changes',
    const HelpOfferCreated('request-a'),
  );
  final entities = _Source<RealtimeEntityChange>(
    'realtime entity changes',
    const RealtimeEntityChange(
      kind: RealtimeEntityKind.inboxItem,
      aggregateId: 'request-a',
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
    ),
  );
  final catchUps = _Source<RealtimeCatchUp>(
    'realtime catch-ups',
    const RealtimeCatchUp(
      accountId: 'viewer',
      connectionEpoch: 2,
      reason: RealtimeCatchUpReason.webSocketReconnected,
    ),
  );

  late final InboxCase inbox = InboxCase(
    _InboxRepository(mutations.stream),
    BeaconThreadsCase(
      _RoomRepository(room.stream),
      work.FakeFactCardRepository(),
      work.FakePollingRepository(),
      work.FakeRoomHints(),
      RoomReadWatermarkStore.testing(),
      // The room singleton's independent own-cursor observer is unrelated to
      // InboxCase's subscription and must not share the probed entity source.
      RealtimeSyncCase(
        _RealtimePort(const Stream.empty(), const Stream.empty()),
      ),
      env: const Env(),
      logger: Logger('room stream lifecycle'),
    ),
    _ForwardRepository(commands.stream, forwards.stream, offers.stream),
    RealtimeSyncCase(_RealtimePort(catchUps.stream, entities.stream)),
    _BookkeepingSignal(bookkeeping.stream),
    BlockCase(_BlockRepository(blocks.stream)),
    env: const Env(),
    logger: Logger('inbox stream lifecycle'),
  );

  List<_Source<dynamic>> get allSources => [
    mutations,
    bookkeeping,
    blocks,
    commands,
    room,
    forwards,
    offers,
    entities,
    catchUps,
  ];
  List<_Source<dynamic>> sourcesFor(String channel) => switch (channel) {
    'local mutations' => [mutations, bookkeeping, blocks],
    'forward commands' => [commands],
    'desk changes' => [room, forwards, offers, entities],
    _ => [catchUps],
  };
  Stream<Object?> streamFor(String channel) => switch (channel) {
    'local mutations' => inbox.localMutations,
    'forward commands' => inbox.forwardCommandCompleted,
    'desk changes' => inbox.deskRelevantChanges,
    _ => inbox.catchUps,
  };
}

class _InboxRepository extends FakeInboxRepository {
  _InboxRepository(this.mutations);
  final Stream<void> mutations;
  @override
  Stream<void> get localMutations => mutations;
}

class _BookkeepingSignal extends BookkeepingRefreshSignal {
  _BookkeepingSignal(this.stream);
  @override
  final Stream<void> stream;
}

class _BlockRepository implements BlockRepository {
  _BlockRepository(this.changes);
  @override
  final Stream<RepositoryEvent<BlockIntent>> changes;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RoomRepository extends work.FakeBeaconThreadsRepository {
  _RoomRepository(this.beaconRoomInvalidations);
  @override
  final Stream<BeaconRoomInvalidation> beaconRoomInvalidations;
}

class _ForwardRepository implements ForwardRepository {
  _ForwardRepository(
    this.forwardCommandCompleted,
    this.forwardChanges,
    this.helpOfferChanges,
  );
  @override
  final Stream<String> forwardCommandCompleted;
  @override
  final Stream<String> forwardChanges;
  @override
  final Stream<HelpOfferEvent> helpOfferChanges;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealtimePort implements RealtimeSyncPort {
  _RealtimePort(this.catchUps, this.entityChanges);
  @override
  final Stream<RealtimeCatchUp> catchUps;
  @override
  final Stream<RealtimeEntityChange> entityChanges;
  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();
  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}
  @override
  Future<void> dispose() async {}
}
