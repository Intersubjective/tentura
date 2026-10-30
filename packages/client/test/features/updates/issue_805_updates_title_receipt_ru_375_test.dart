// #805: Updates history title fits at 375 px in RU; postExpiringSoon reads in RU.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/screen/updates_screen.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';
import '../../support/noop_attention_actor_profiles.dart';

class _HarnessRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

class _HistoryFeedRepo extends AttentionRepositoryFake {
  _HistoryFeedRepo(this._items);

  final List<AttentionReceipt> _items;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    return AttentionFeed(
      summary: AttentionSummary(unreadTotal: _items.length),
      page: AttentionFeedPage(items: _items),
    );
  }

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

AttentionReceipt _postExpiringReceipt() => AttentionReceipt(
  id: 'r-expiring',
  category: 'requestProgress',
  kind: 'postExpiringSoon',
  priority: 'high',
  title: 'Your post is about to expire',
  body: 'Your post expires in under 3 hours',
  actionUrl: '/#/view/P1?is_deep_link=true',
  createdAt: DateTime.utc(2026, 10, 30, 12),
  collapsedCount: 1,
  presentationKey: 'post_expiring_soon',
  presentationPayloadJson: '{"eventType":"postExpiringSoon","beaconId":"P1"}',
  surface: AttentionSurface.activity,
  beaconId: 'P1',
);

Future<void> _pumpUpdatesHistory(
  WidgetTester tester, {
  required _HistoryFeedRepo repository,
}) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repository,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('issue-805-updates-test'),
  );
  accounts.emit('viewer');

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  ensureNoopAttentionActorProfilesRegistered();
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('issue-805-updates-test'));
  }
  addTearDown(() async {
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (GetIt.I.isRegistered<Logger>()) {
      GetIt.I.unregister<Logger>();
    }
  });

  final router = _HarnessRouter();
  await tester.pumpWidget(
    RouterScope(
      controller: router,
      stateHash: 0,
      inheritableObserversBuilder: () => const [],
      child: StackRouterScope(
        controller: router,
        stateHash: 0,
        child: MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: kPhoneSurface),
            child: TenturaResponsiveScope(child: const UpdatesScreen()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _expectTitleWhole(WidgetTester tester, String title) {
  final finder = find.text(title);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.text.toPlainText(), title);
  expect(paragraph.didExceedMaxLines, isFalse);
}

void main() {
  testWidgets('RU 375×667: «Обновления» fits; post expiry row is Russian', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final ru = lookupL10n(const Locale('ru'));
    await _pumpUpdatesHistory(
      tester,
      repository: _HistoryFeedRepo([_postExpiringReceipt()]),
    );

    _expectTitleWhole(tester, ru.notificationHistoryTitle);
    expect(find.textContaining('Пост скоро истечёт'), findsOneWidget);
    expect(find.textContaining('about to expire'), findsNothing);
    expect(find.byType(UpdatesFeedTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
