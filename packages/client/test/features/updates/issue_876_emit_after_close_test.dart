import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

/// #876 (Sentry TENTURA-CLIENT-5K) — the Updates screen is closed while an
/// await inside [UpdatesFeedCubit] is still pending (a row opened, then the
/// user navigates away). When the await settles, the cubit must not emit:
/// `emit` after `close` throws `StateError`.
///
/// Real path: [UpdatesFeedCubit] → real [AttentionCase] → a repository fake
/// whose writes and reads are held open by completers.
void main() {
  late _Accounts accounts;
  late _Repository repository;
  late TestRealtimeSyncPort realtime;
  late RealtimeSyncCase realtimeCase;
  late AttentionCase attention;
  late UpdatesFeedCubit cubit;

  setUp(() async {
    accounts = _Accounts();
    repository = _Repository();
    final sync = buildTestRealtimeSync();
    realtime = sync.port;
    realtimeCase = sync.case_;
    attention = AttentionCase(
      repository,
      accounts,
      realtimeCase,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('issue-876'),
    );
    cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activityStream,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: realtimeCase,
      logger: Logger('issue-876-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    accounts.emit('viewer');
    await _settle();
    expect(cubit.state.items, hasLength(1));
    expect(cubit.state.hasNextPage, isTrue);
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    await attention.dispose();
    await realtime.dispose();
    await accounts.close();
  });

  for (final fail in [false, true]) {
    final outcome = fail ? 'fails' : 'succeeds';

    test('markRead: markSeen $outcome after close → no emit', () async {
      final gate = Completer<int>();
      repository.markSeenGate = gate;

      final pending = cubit.markRead('r1');
      await _settle();
      expect(repository.markSeenCalls, 1, reason: 'the write is in flight');
      await cubit.close();

      if (fail) {
        gate.completeError(StateError('offline'));
      } else {
        gate.complete(1);
      }
      await expectLater(pending, completes);
    });

    test('refresh: head fetch $outcome after close → no emit', () async {
      final gate = Completer<AttentionFeed>();
      repository.fetchGates.add(gate);

      final pending = cubit.refresh();
      await _settle();
      await cubit.close();

      if (fail) {
        gate.completeError(StateError('offline'));
      } else {
        gate.complete(_feed());
      }
      await expectLater(pending, completes);
    });
  }

  test('loadNextPage: page fetch fails after close → no emit', () async {
    final gate = Completer<AttentionFeed>();
    repository.fetchGates.add(gate);

    final pending = cubit.loadNextPage();
    await _settle();
    expect(repository.cursors.last, 'page-two', reason: 'tail is in flight');
    await cubit.close();

    gate.completeError(StateError('offline'));
    await expectLater(pending, completes);
  });
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository extends AttentionRepositoryFake {
  /// Held fetches, answered in order; empty → the first page answers at once.
  final fetchGates = <Completer<AttentionFeed>>[];
  final cursors = <String?>[];
  Completer<int>? markSeenGate;
  int markSeenCalls = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    cursors.add(cursor);
    if (fetchGates.isNotEmpty) return fetchGates.removeAt(0).future;
    return _feed();
  }

  @override
  Future<int> markSeen(List<String> ids) {
    markSeenCalls++;
    return markSeenGate?.future ?? Future.value(ids.length);
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

AttentionFeed _feed() => AttentionFeed(
  summary: const AttentionSummary(unreadTotal: 1),
  page: AttentionFeedPage(
    items: [
      AttentionReceipt(
        id: 'r1',
        category: 'social',
        kind: 'mutualConnectionFormed',
        priority: 'normal',
        title: 'Vadim · New connection',
        body: 'You are now connected on Tentura.',
        actionUrl: '/#/',
        createdAt: DateTime.utc(2026, 10, 31, 9),
        collapsedCount: 1,
        presentationPayloadJson: '{}',
        surface: AttentionSurface.activity,
      ),
    ],
    nextCursor: 'page-two',
  ),
);

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
