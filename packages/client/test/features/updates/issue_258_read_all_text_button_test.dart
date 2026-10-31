// #258: the bulk «Read all» in Updates is a text button at every width,
// never an icon-only ✓✓ (ichorid 2026-10-31: on phones the glyph is why
// nobody found it). It stays visible but disabled when nothing is unread, the
// search toggle stays an icon, and the bar fits at 375×667 in RU and EN.

import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:tentura/features/updates/ui/widget/updates_feed_app_bar.dart';
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

Future<void> _pumpUpdatesHistory(
  WidgetTester tester, {
  required _HistoryFeedRepo repository,
  required Locale locale,
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repository,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('issue-258-updates-test'),
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
    GetIt.I.registerSingleton<Logger>(Logger('issue-258-updates-test'));
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
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: const TenturaResponsiveScope(child: UpdatesScreen()),
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

AttentionReceipt _unread(String id) => AttentionReceipt(
  id: id,
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

/// Laid out whole: one line, nothing ellipsised or clipped.
void _expectWholeLine(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.size.width + 0.5),
      reason: '«$text» is clipped',
    );
  }
}

/// The app font (Inter), as in beacon_surface_tabs_360_labels_test: the test
/// font's 1 em glyphs are far wider than any real label, so fit is measured
/// with the font the app ships.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

const _desktop = Size(1280, 800);

final _cases = [
  (const Locale('ru'), kPhoneSurface, 'RU 375×667'),
  (const Locale('en'), kPhoneSurface, 'EN 375×667'),
  (const Locale('ru'), _desktop, 'RU desktop'),
  (const Locale('en'), _desktop, 'EN desktop'),
];

Future<void> _pumpRow(
  WidgetTester tester, {
  required Locale locale,
  required Size size,
  required bool hasUnread,
  required VoidCallback onMarkAll,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Builder(
            builder: (context) {
              final l10n = L10n.of(context)!;
              return Scaffold(
                appBar: TenturaTopBar.of(
                  context,
                  title: const SizedBox.shrink(),
                  row: UpdatesFeedAppBarRow(
                    title: l10n.notificationHistoryTitle,
                    markAllLabel: l10n.updatesMarkAllSeen,
                    hasUnread: hasUnread,
                    onMarkAll: onMarkAll,
                    showSearchIcon: context.windowClass == WindowClass.compact,
                    searchOpen: false,
                    onSearchPressed: () {},
                    searchTooltip: l10n.updatesSearchHint,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(_loadInter);

  for (final (locale, size, label) in _cases) {
    final l10n = lookupL10n(locale);
    final phone = size == kPhoneSurface;

    testWidgets('#258 $label: pane title row shows «Read all» as text', (
      tester,
    ) async {
      var taps = 0;
      await _pumpRow(
        tester,
        locale: locale,
        size: size,
        hasUnread: true,
        onMarkAll: () => taps++,
      );

      expect(find.byIcon(Icons.done_all_outlined), findsNothing);
      final action = find.widgetWithText(
        TenturaTextAction,
        l10n.updatesMarkAllSeen,
      );
      expect(action, findsOneWidget);
      expect(find.byIcon(Icons.search), phone ? findsOneWidget : findsNothing);
      _expectWholeLine(tester, l10n.updatesMarkAllSeen);
      _expectWholeLine(tester, l10n.notificationHistoryTitle);
      expect(tester.takeException(), isNull);

      await tester.tap(action);
      expect(taps, 1);
    });

    testWidgets('#258 $label: pane «Read all» stays shown, disabled', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        locale: locale,
        size: size,
        hasUnread: false,
        onMarkAll: () {},
      );
      final action = tester.widget<TenturaTextAction>(
        find.widgetWithText(TenturaTextAction, l10n.updatesMarkAllSeen),
      );
      expect(action.onPressed, isNull);
      expect(find.byIcon(Icons.done_all_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final unread in [true, false]) {
      testWidgets(
        '#258 $label: Updates screen top bar «Read all» is text '
        '(${unread ? 'enabled' : 'disabled'})',
        (tester) async {
          await _pumpUpdatesHistory(
            tester,
            repository: _HistoryFeedRepo([if (unread) _unread('r1')]),
            locale: locale,
            size: size,
          );

          expect(find.byIcon(Icons.done_all_outlined), findsNothing);
          final actions = find.descendant(
            of: find.byType(AppBar),
            matching: find.widgetWithText(
              TenturaTextAction,
              l10n.updatesMarkAllSeen,
            ),
          );
          expect(actions, findsOneWidget);
          expect(
            tester.widget<TenturaTextAction>(actions).onPressed == null,
            !unread,
          );
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.byIcon(Icons.search),
            ),
            phone ? findsOneWidget : findsNothing,
          );
          _expectWholeLine(tester, l10n.updatesMarkAllSeen);
          _expectWholeLine(tester, l10n.notificationHistoryTitle);
          // Readable: scaled down at most a little, never clipped.
          final title = find.text(l10n.notificationHistoryTitle);
          final laidOut = tester.renderObject<RenderParagraph>(title).size;
          expect(
            tester.getRect(title).width / laidOut.width,
            greaterThanOrEqualTo(0.8),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
