import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/platform/tab_attention_indicator.dart';
import 'package:tentura/design_system/tentura_tab_indicator.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';
import 'package:tentura/ui/widget/tab_attention_scope.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';

typedef TabAttentionApplyRecord = ({
  TabAttentionDisplay display,
  String baseTitle,
  (bool, String) titleKey,
  (bool, int) badgeKey,
});

/// Records every [apply] call with channel keys derived from call arguments.
/// Does not skip calls — production controller pacing owns that.
final class RecordingTabAttentionIndicator extends TabAttentionIndicator {
  RecordingTabAttentionIndicator({bool isBackground = false})
    : _isBackground = isBackground;

  final _backgroundController = StreamController<bool>.broadcast();
  bool _isBackground;
  final records = <TabAttentionApplyRecord>[];

  @override
  Stream<bool> get backgroundChanges => _backgroundController.stream;

  @override
  bool get isBackground => _isBackground;

  void setBackground(bool background) {
    if (_isBackground == background) return;
    _isBackground = background;
    _backgroundController.add(background);
  }

  @override
  void apply(
    TabAttentionDisplay display,
    TenturaTabIndicatorStyle style, {
    required String baseTitle,
  }) {
    records.add((
      display: display,
      baseTitle: baseTitle,
      titleKey: (_isBackground, display.label),
      badgeKey: (_isBackground, display.count),
    ));
  }

  @override
  void dispose() {
    if (!_backgroundController.isClosed) {
      unawaited(_backgroundController.close());
    }
  }
}

final class ControllableAttentionAccounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> dispose() => _changes.close();
}

final class ControllableAttentionRepository implements AttentionRepositoryPort {
  final List<Completer<AttentionFeed>> pendingFetches = [];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) => pendingFetches.removeAt(0).future;

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      const {};

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> settle({
    required String receiptId,
    required String kind,
  }) async => 0;
}

AttentionFeed buildAttentionFeed({int unread = 1}) => AttentionFeed(
  summary: AttentionSummary(unreadTotal: unread),
  page: AttentionFeedPage(
    items: [
      AttentionReceipt(
        id: 'receipt-$unread',
        category: 'asksOfMe',
        kind: 'needsMe',
        priority: 'normal',
        title: 'Title',
        body: 'Body',
        actionUrl: '/#/',
        createdAt: DateTime.utc(2026),
        collapsedCount: 1,
        presentationPayloadJson: '{}',
      ),
    ],
  ),
);

/// Same real-async microtask drain as [updates_feed_cubit_test.dart].
Future<void> settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> waitThrottleWindow() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

Future<void> seedUnread({
  required ControllableAttentionAccounts accounts,
  required ControllableAttentionRepository repository,
  required int unread,
  String accountId = 'account-a',
}) async {
  final completer = Completer<AttentionFeed>();
  repository.pendingFetches.add(completer);
  accounts.emit(accountId);
  await settle();
  completer.complete(buildAttentionFeed(unread: unread));
  await settle();
}

Future<void> pushUnread({
  required ControllableAttentionRepository repository,
  required RealtimeSyncCase realtimeCase,
  required int unread,
}) async {
  final completer = Completer<AttentionFeed>();
  repository.pendingFetches.add(completer);
  realtimeCase.requestCatchUp(RealtimeCatchUpReason.appResumed);
  await settle();
  completer.complete(buildAttentionFeed(unread: unread));
  await settle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabAttentionController pacing', () {
    late ControllableAttentionRepository repository;
    late ControllableAttentionAccounts accounts;
    late TestRealtimeSyncPort realtimePort;
    late RealtimeSyncCase realtimeCase;
    late AttentionCase attention;
    late RecordingTabAttentionIndicator indicator;
    late TabAttentionController controller;

    setUp(() {
      repository = ControllableAttentionRepository();
      accounts = ControllableAttentionAccounts();
      final sync = buildTestRealtimeSync();
      realtimePort = sync.port;
      realtimeCase = sync.case_;
      attention = AttentionCase(
        repository,
        accounts,
        realtimeCase,
        noopBlockCase(),
        Logger('tab-attention-scope-test'),
      );
      indicator = RecordingTabAttentionIndicator(isBackground: true);
      controller = TabAttentionController(
        indicator: indicator,
        attention: attention,
      );
    });

    tearDown(() async {
      controller.dispose();
      await attention.dispose();
      await realtimePort.dispose();
      await accounts.dispose();
    });

    test('applies matching display and base title when background', () async {
      await seedUnread(
        accounts: accounts,
        repository: repository,
        unread: 3,
      );

      expect(indicator.records, isNotEmpty);
      final last = indicator.records.last;
      expect(last.display, (count: 3, label: '3'));
      expect(last.baseTitle, 'Tentura');
      expect(last.titleKey, (true, '3'));
      expect(last.badgeKey, (true, 3));
    });

    test(
      'setBaseTitle stores while active; clear sync-applies stored title',
      () async {
        await seedUnread(
          accounts: accounts,
          repository: repository,
          unread: 2,
        );

        final beforeActive = indicator.records.length;
        controller.setBaseTitle('Тентура');
        await settle();
        expect(
          indicator.records.length,
          beforeActive,
          reason: 'setBaseTitle must not apply while attention is active',
        );

        indicator.setBackground(false);
        await settle();
        expect(indicator.records.last.display, tabAttentionNone);
        expect(
          indicator.records.last.baseTitle,
          'Тентура',
          reason: 'clear must use the stored localized base title',
        );

        final beforeClearLocale = indicator.records.length;
        controller.setBaseTitle('Tentura');
        await settle();
        expect(indicator.records.length, beforeClearLocale + 1);
        expect(indicator.records.last.display, tabAttentionNone);
        expect(indicator.records.last.baseTitle, 'Tentura');
      },
    );

    test(
      '100→101 calls adapter again after throttle window; badge key changes',
      () async {
        await seedUnread(
          accounts: accounts,
          repository: repository,
          unread: 100,
        );
        await waitThrottleWindow();

        final before = indicator.records.length;
        final prior = indicator.records.last;
        expect(prior.display, (count: 100, label: '99+'));
        expect(prior.titleKey, (true, '99+'));
        expect(prior.badgeKey, (true, 100));

        await pushUnread(
          repository: repository,
          realtimeCase: realtimeCase,
          unread: 101,
        );

        expect(indicator.records.length, before + 1);
        final latest = indicator.records.last;
        expect(latest.display, (count: 101, label: '99+'));
        expect(latest.titleKey, prior.titleKey);
        expect(latest.badgeKey, (true, 101));
        expect(latest.badgeKey, isNot(prior.badgeKey));
      },
    );

    test('leading-edge throttle keeps only the latest value', () async {
      await seedUnread(
        accounts: accounts,
        repository: repository,
        unread: 1,
      );
      expect(indicator.records.last.display.count, 1);
      final afterLeading = indicator.records.length;

      await pushUnread(
        repository: repository,
        realtimeCase: realtimeCase,
        unread: 2,
      );
      await pushUnread(
        repository: repository,
        realtimeCase: realtimeCase,
        unread: 3,
      );

      expect(
        indicator.records.length,
        afterLeading,
        reason: 'coalesced updates stay pending inside the 250ms window',
      );
      expect(
        indicator.records.where((record) => record.display.count == 2),
        isEmpty,
      );

      await waitThrottleWindow();
      expect(indicator.records.length, afterLeading + 1);
      expect(indicator.records.last.display.count, 3);
    });

    test('clear bypasses throttle synchronously inside open window', () async {
      await seedUnread(
        accounts: accounts,
        repository: repository,
        unread: 1,
      );

      await pushUnread(
        repository: repository,
        realtimeCase: realtimeCase,
        unread: 2,
      );

      indicator.setBackground(false);
      await settle();

      expect(indicator.records.last.display, tabAttentionNone);
      expect(indicator.records.last.titleKey, (false, ''));
      expect(indicator.records.last.badgeKey, (false, 0));
    });

    test('account switch cannot repaint stale pending unread', () async {
      await seedUnread(
        accounts: accounts,
        repository: repository,
        unread: 5,
      );

      await pushUnread(
        repository: repository,
        realtimeCase: realtimeCase,
        unread: 9,
      );

      final clearCompleter = Completer<AttentionFeed>();
      repository.pendingFetches.add(clearCompleter);
      accounts.emit('account-b');
      await settle();
      clearCompleter.complete(buildAttentionFeed(unread: 0));
      await settle();

      await waitThrottleWindow();

      expect(
        indicator.records.where((record) => record.display.count == 9),
        isEmpty,
      );
      expect(indicator.records.last.display, tabAttentionNone);
    });

    test('dispose clears indicator', () async {
      await seedUnread(
        accounts: accounts,
        repository: repository,
        unread: 4,
      );

      indicator.records.clear();
      controller.dispose();

      expect(indicator.records, isNotEmpty);
      expect(indicator.records.last.display, tabAttentionNone);

      // Prevent tearDown double-dispose; rebuild a disposable controller stub.
      controller = TabAttentionController(
        indicator: RecordingTabAttentionIndicator(),
      );
    });
  });

  group('TabAttentionScope lifecycle', () {
    testWidgets(
      'DI-safe create, localized clear reporter, dispose clears without brightness apply',
      (tester) async {
        final indicator = RecordingTabAttentionIndicator();

        await tester.pumpWidget(
          TabAttentionScope(
            indicator: indicator,
            child: MaterialApp(
              locale: const Locale('ru'),
              supportedLocales: L10n.supportedLocales,
              localizationsDelegates: L10n.localizationsDelegates,
              builder: (context, child) => TabAttentionBaseTitleReporter(
                child: child ?? const SizedBox(),
              ),
              home: const SizedBox(),
            ),
          ),
        );
        await tester.pump();

        expect(indicator.records, isNotEmpty);
        expect(indicator.records.last.display, tabAttentionNone);
        expect(indicator.records.last.baseTitle, 'Тентура');

        indicator.records.clear();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();

        expect(indicator.records, isNotEmpty);
        expect(indicator.records.last.display, tabAttentionNone);

        final afterDispose = indicator.records.length;
        final binding = tester.platformDispatcher;
        binding.platformBrightnessTestValue = Brightness.dark;
        addTearDown(binding.clearPlatformBrightnessTestValue);
        tester.binding.handlePlatformBrightnessChanged();
        await tester.pump();

        expect(indicator.records.length, afterDispose);
      },
    );
  });
}
