import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligations_pane.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';
import 'support/noop_invite_setup_port.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _SummaryRepository implements AttentionRepositoryPort {
  _SummaryRepository(this.summary);

  final AttentionSummary summary;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async {
    return AttentionFeed(
      summary: summary,
      page: const AttentionFeedPage(),
    );
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Widget _wrap(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(800, 800)),
    child: TenturaResponsiveScope(
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  test('Activity default offered views are All and Unread only', () {
    expect(
      UpdatesFeedPane.kDefaultUpdatesFeedOfferedViews,
      [AttentionView.all, AttentionView.unread],
    );
  });

  testWidgets('Activity feed shows All and Unread tabs only', (tester) async {
    final accounts = _Accounts();
    final repository = _SummaryRepository(
      const AttentionSummary(unreadTotal: 2, needsYouTotal: 5),
    );
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      repository,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-feed-views-activity'),
    );
    accounts.emit('viewer');
    await _drain();

    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activity,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('activity-views'),
    );
    await _drain();

    await tester.pumpWidget(
      _wrap(
        BlocProvider.value(
          value: cubit,
          child: const UpdatesFeedPane(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('updates-all')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('updates-unread')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('updates-needs-you')),
      findsNothing,
    );

    unawaited(cubit.close());
    unawaited(attention.dispose());
    unawaited(sync.port.dispose());
    unawaited(accounts.close());
  });

  testWidgets(
    'Activity unread tab count ignores needs-you total',
    (tester) async {
      const unreadOnly = 4;
      const needsYouOnly = 11;
      final accounts = _Accounts();
      final repository = _SummaryRepository(
        AttentionSummary(unreadTotal: unreadOnly, needsYouTotal: needsYouOnly),
      );
      final sync = buildTestRealtimeSync();
      final attention = AttentionCase(
        repository,
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('updates-feed-views-unread-badge'),
      );
      accounts.emit('viewer');
      await _drain();

      final cubit = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.activity,
        attention: attention,
        setup: NoopInviteAcceptedSetupPort(),
        realtime: sync.case_,
        logger: Logger('activity-unread-badge'),
      );
      await _drain();

      await tester.pumpWidget(
        _wrap(
          BlocProvider.value(
            value: cubit,
            child: const UpdatesFeedPane(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(cubit.state.summary.unreadTotal, unreadOnly);
      expect(cubit.state.summary.needsYouTotal, needsYouOnly);
      expect(find.text('$unreadOnly'), findsOneWidget);
      expect(find.text('$needsYouOnly'), findsNothing);

      unawaited(cubit.close());
      unawaited(attention.dispose());
      unawaited(sync.port.dispose());
      unawaited(accounts.close());
    },
  );

  testWidgets('My Work obligations pane mounts the needs-you feed', (
    tester,
  ) async {
    final accounts = _Accounts();
    final repository = _SummaryRepository(
      const AttentionSummary(needsYouTotal: 1),
    );
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      repository,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('updates-feed-views-my-work'),
    );
    GetIt.I.registerSingleton<AttentionCase>(attention);
    GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
      NoopInviteAcceptedSetupPort(),
    );
    GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
    final registeredLogger = !GetIt.I.isRegistered<Logger>();
    if (registeredLogger) {
      GetIt.I.registerSingleton<Logger>(Logger('updates-feed-views-my-work-pane'));
    }
    accounts.emit('viewer');
    await _drain();

    await tester.pumpWidget(
      _wrap(const MyWorkObligationsPane()),
    );
    await tester.pump();
    await _drain();
    await tester.pump();

    expect(find.byKey(const Key(TestIds.myWorkObligationsPane)), findsOneWidget);
    final l10n = L10n.of(tester.element(find.byType(Scaffold)))!;
    expect(find.text(l10n.updatesEmptyNeedsYouHint), findsOneWidget);

    unawaited(attention.dispose());
    unawaited(sync.port.dispose());
    unawaited(accounts.close());
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (registeredLogger && GetIt.I.isRegistered<Logger>()) {
      GetIt.I.unregister<Logger>();
    }
  });
}
