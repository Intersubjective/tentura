import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository extends AttentionRepositoryFake {
  final pendingFetches = <Completer<AttentionFeed>>[];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) => pendingFetches.removeAt(0).future;

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

AttentionReceipt _receipt({String id = 'receipt-1'}) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Title',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
);

AttentionFeed _feed({List<AttentionReceipt>? items}) => AttentionFeed(
  summary: const AttentionSummary(unreadTotal: 1),
  page: AttentionFeedPage(items: items ?? [_receipt()]),
);

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Accounts accounts;
  late _Repository repository;
  late TestRealtimeSyncPort realtime;
  late RealtimeSyncCase realtimeCase;
  late AttentionCase attention;
  late UpdatesFeedCubit cubit;

  setUp(() {
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
      Logger('updates-feed-cubit-test'),
    );
  });

  tearDown(() async {
    await cubit.close();
    await attention.dispose();
    await realtime.dispose();
    await accounts.close();
  });

  test('failed refresh keeps loaded items and exposes a retryable error', () async {
    final initial = Completer<AttentionFeed>();
    final failing = Completer<AttentionFeed>();
    final retry = Completer<AttentionFeed>();
    repository.pendingFetches.addAll([initial, failing, retry]);
    cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activity,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: realtimeCase,
      logger: Logger('updates-feed-cubit-test'),
    );
    accounts.emit('account-a');
    await _settle();
    initial.complete(_feed(items: [_receipt()]));
    await _settle();

    expect(cubit.state.items, hasLength(1));
    expect(cubit.state.hasRefreshError, isFalse);

    final refresh = cubit.refresh();
    await _settle();
    failing.completeError(StateError('offline'));
    await refresh;
    await _settle();

    expect(cubit.state.hasRefreshError, isTrue);
    expect(cubit.state.items, hasLength(1));
    expect(cubit.state.status, isA<StateIsSuccess>());

    retry.complete(_feed(items: [_receipt(id: 'r2')]));
    await cubit.refresh();
    await _settle();

    expect(cubit.state.hasRefreshError, isFalse);
    expect(cubit.state.items, hasLength(1));
    expect(cubit.state.items.single.id, 'r2');
  });
}
