import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/attention/ui/widget/request_attention_timeline_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';

/// U17b — the Timeline has **one** entry point, and it speaks History's voice.
///
/// Before this unit three surfaces answered "show me what happened on this
/// Request" three different ways: For You's pinned card and My Desk pushed the
/// Request detail, and For You's stream card went through
/// `RootRouter.openFromUpdate`, whose destination map can route a receipt to a
/// profile or the review screen instead. Meanwhile
/// `AttentionCase.requestHistory` — the §9 read that *is* the timeline — had
/// no UI caller at all.
void main() {
  group('one entry point', () {
    // Directory-wide on purpose, for the reason `single_attention_owner_test`
    // states: a guard that lists today's three call sites lets the fourth one
    // walk straight past it.
    test('every surface routes onOpenTimeline to the one sheet', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('/_g/') ||
            entity.path.endsWith('.g.dart') ||
            entity.path.endsWith('.freezed.dart')) {
          continue;
        }
        final source = entity.readAsStringSync();
        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!line.contains('onOpenTimeline:')) continue;
          // A pass-through hands the caller's callback down; it is not a
          // destination and decides nothing.
          final argument = line.split('onOpenTimeline:').last.trim();
          if (argument.startsWith('onOpenTimeline') ||
              argument.startsWith('widget.onOpenTimeline') ||
              argument.startsWith('this.onOpenTimeline')) {
            continue;
          }
          // Otherwise this is a destination: the next few lines must name the
          // single entry point.
          final window = lines
              .sublist(i, (i + 4).clamp(0, lines.length))
              .join('\n');
          if (!window.contains('showRequestAttentionTimelineSheet')) {
            offenders.add('${entity.path}:${i + 1}: $argument');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'the Timeline control must open the Request timeline (§9), '
            'not a route of the call site\'s own choosing',
      );
    });
  });

  group('the sheet', () {
    late _TimelineRepository repository;
    late _Accounts accounts;
    late AttentionCase attention;
    late TestRealtimeSyncPort realtimePort;

    setUp(() async {
      repository = _TimelineRepository();
      accounts = _Accounts();
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      attention = AttentionCase(
        repository,
        accounts,
        realtime.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('request-attention-timeline-sheet'),
      );
      GetIt.I.registerSingleton<AttentionCase>(attention);
    });

    tearDown(() async {
      await GetIt.I.reset();
      await attention.dispose();
      await accounts.close();
      await realtimePort.dispose();
    });

    testWidgets('renders the event headline, not the Request headline', (
      tester,
    ) async {
      // §8a — "Object headlines on For You, event headlines in History". The
      // timeline is a chronological receipt log, so it reads as the event.
      repository.pages.add(
        AttentionFeedPage(
          items: [
            // As the server sends it: `title` is the event, and the Request
            // title travels in the presentation payload.
            _receipt(
              id: 'e-1',
              title: 'Пётр предложил помощь',
              body: '',
              presentationKey: 'help_offer_submitted',
              payloadJson: '{"beaconTitle":"Нужна помощь с переездом"}',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(const RequestAttentionTimelineSheet(beaconId: 'B-1')),
      );
      await tester.pumpAndSettle();

      expect(repository.calls.single.beaconId, 'B-1');
      // Precisely: the *headline* is the event. Asserting the text is merely
      // present would pass with the event sitting in the body line and the
      // Request title heading the row — which is For You's voice, not
      // History's.
      final headline = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(RequestAttentionTimelineSheet),
              matching: find.byType(Text),
            )
            .at(1),
      );
      expect(
        headline.data,
        'Пётр предложил помощь',
        reason: 'the event is the subject on this surface (§8a)',
      );
      // The Request title is not absent from the row — it is not the
      // *headline*. On For You the two swap places (§8a).
      expect(find.text('Нужна помощь с переездом'), findsOneWidget);
    });

    testWidgets('paginates with the cursor the server returned', (
      tester,
    ) async {
      repository.pages.add(
        AttentionFeedPage(
          nextCursor: 'cursor-2',
          items: [
            for (var i = 0; i < 20; i++)
              _receipt(id: 'e-$i', body: 'Событие $i'),
          ],
        ),
      );
      repository.pages.add(
        AttentionFeedPage(
          items: [_receipt(id: 'e-20', body: 'Событие 20')],
        ),
      );

      await tester.pumpWidget(
        _wrap(const RequestAttentionTimelineSheet(beaconId: 'B-1')),
      );
      await tester.pumpAndSettle();
      expect(repository.calls.length, 1);
      expect(repository.calls.single.cursor, isNull);
      expect(
        repository.calls.single.limit,
        RequestAttentionTimelineSheet.pageSize,
      );

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(
        repository.calls.length,
        2,
        reason: 'reaching the end asks for the next page',
      );
      expect(repository.calls.last.cursor, 'cursor-2');

      // The second page is in the list, and the timeline stops there: a page
      // with no cursor is the end of it.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Событие 20'), findsOneWidget);
      expect(
        repository.calls.length,
        2,
        reason: 'a page without a cursor is the end — no endless refetch',
      );
    });

    testWidgets('a failed load says so instead of showing an empty log', (
      tester,
    ) async {
      repository.failNext = true;

      await tester.pumpWidget(
        _wrap(const RequestAttentionTimelineSheet(beaconId: 'B-1')),
      );
      await tester.pumpAndSettle();

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.updatesRefreshFailedBanner), findsOneWidget);
      expect(
        find.text(l10n.updatesEmptyAllHint),
        findsNothing,
        reason: '"nothing happened here" is a different claim from "I could '
            'not find out" (§4 honest failure)',
      );
    });
  });
}

AttentionReceipt _receipt({
  required String id,
  String title = 'Request',
  String body = 'Body',
  String? presentationKey,
  String payloadJson = '{}',
}) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 18),
  collapsedCount: 1,
  presentationPayloadJson: payloadJson,
  presentationKey: presentationKey,
  beaconId: 'B-1',
  surface: AttentionSurface.activity,
);

typedef _HistoryCall = ({String beaconId, String? cursor, int limit});

final class _TimelineRepository extends AttentionRepositoryFake {
  final List<AttentionFeedPage> pages = [];
  final List<_HistoryCall> calls = [];
  bool failNext = false;

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    calls.add((beaconId: beaconId, cursor: cursor, limit: limit));
    if (failNext) {
      failNext = false;
      throw StateError('history unavailable');
    }
    return pages.isEmpty ? const AttentionFeedPage() : pages.removeAt(0);
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

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

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  Future<void> close() => _changes.close();
}

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(800, 800)),
  child: TenturaResponsiveScope(
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  ),
);
