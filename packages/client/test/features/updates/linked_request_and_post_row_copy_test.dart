import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_request_history.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_request_history.req.gql.dart';
import 'package:tentura/features/attention/ui/widget/request_attention_timeline_sheet.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/attention_case_factory.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

// Rows for a linked Request and for a Post, read the way the server sends
// them: wire JSON → AttentionRepository → the request timeline sheet and the
// Updates/Activity tile.

const _beaconId = 'Bbeacon000001';

/// One receipt in the JSON shape of the `AttentionReceiptFields` fragment.
Map<String, dynamic> _wire({
  required String key,
  required Map<String, Object?> payload,
  int beaconKind = 0,
  String? relatedBeaconTitle,
  String? postRootExcerpt,
  String? beaconAuthorName,
  String title = 'Server title',
}) => {
  '__typename': 'AttentionReceipt',
  'id': 'r-$key',
  'category': 'requestProgress',
  'kind': 'roomActivityLowPriority',
  'priority': 'normal',
  'title': title,
  'body': '',
  'actionUrl': '/#/',
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': _beaconId,
  'coordinationItemId': null,
  'actorUserId': null,
  'sourceEventKey': null,
  'destinationKind': 'beacon',
  'targetEntityId': _beaconId,
  'presentationKey': key,
  'presentationPayloadJson': jsonEncode(payload),
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': null,
  'clearReason': null,
  'surface': 'activity',
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'eventTotal': null,
  'eventUnseenCount': null,
  'provenanceJson': null,
  'beaconAuthorId': 'Uauthor000001',
  'beaconAuthorName': beaconAuthorName,
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': false,
  'beaconTitle': beaconKind == 1 ? '' : 'Parent request',
  'relatedBeaconTitle': relatedBeaconTitle,
  'beaconKind': beaconKind,
  'postRootExcerpt': postRootExcerpt,
  'postRootImageId': null,
  'eventsPreview': <Map<String, dynamic>>[],
};

const _anna = Profile(id: 'Uanna000000001', displayName: 'Anna');

Map<String, dynamic> _deadlineWire(DateTime deadline) {
  final iso = deadline.toUtc().toIso8601String();
  return _wire(
    key: 'deadline_changed',
    title: 'Deadline changed',
    payload: {
      'eventType': 'deadlineChanged',
      'beaconId': _beaconId,
      'actorUserId': _anna.id,
      'actorName': _anna.displayName,
      'newEndAt': iso,
    },
  )..addAll({
    'category': 'coordination',
    'kind': 'deadlineChanged',
    'actorUserId': _anna.id,
    'body': 'Deadline changed from none to $iso',
  });
}

Map<String, Object?> _linkedPayload() => {
  'eventType': 'beaconHierarchyStatusChanged',
  'personal': true,
  'beaconId': _beaconId,
  'targetEntityId': _beaconId,
  'toStatus': 'closed',
  'fromStatus': 'open',
};

Map<String, Object?> _replyPayload() => {
  'eventType': 'postFirstResponse',
  'personal': true,
  'actorName': 'Bob',
  'actorUserId': 'Ubob000000001',
  'beaconId': _beaconId,
  'targetEntityId': _beaconId,
  'excerpt': '',
};

Map<String, Object?> _expiringPayload(DateTime expiresAt) => {
  'eventType': 'postExpiringSoon',
  'personal': true,
  'beaconId': _beaconId,
  'targetEntityId': _beaconId,
  'expiresAt': expiresAt.toUtc().toIso8601String(),
};

final class _Remote implements RemoteRequestClient {
  List<Map<String, dynamic>> items = const [];

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    final Object? data;
    if (request is GAttentionRequestHistoryReq) {
      data = GAttentionRequestHistoryData.fromJson({
        '__typename': 'query_root',
        'attentionRequestHistory': {
          '__typename': 'AttentionPage',
          'nextCursor': null,
          'items': items,
        },
      });
    } else if (request is GAttentionFeedReq) {
      data = GAttentionFeedData.fromJson({
        '__typename': 'query_root',
        'attentionFeed': {
          '__typename': 'AttentionFeed',
          'summary': {
            '__typename': 'AttentionSummary',
            'unreadTotal': items.length,
            'needsYouTotal': 0,
          },
          'page': {
            '__typename': 'AttentionPage',
            'nextCursor': null,
            'items': items,
          },
        },
      });
    } else {
      throw UnsupportedError('Unexpected operation: $request');
    }
    return Stream.value(
      OperationResponse<TData, TVars>(
        operationRequest: request,
        dataSource: DataSource.Link,
        data: data as TData,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  Future<void> close() => _changes.close();
}

Widget _wrap(
  Locale locale,
  Widget child, {
  Size size = const Size(800, 800),
}) => MediaQuery(
  data: MediaQueryData(size: size),
  child: TenturaResponsiveScope(
    child: MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  final remote = _Remote();
  final repository = AttentionRepository(remote);

  Future<AttentionReceipt> mapped(Map<String, dynamic> wire) async {
    remote.items = [wire];
    return (await repository.fetch(
      view: AttentionView.all,
    )).page.items.single;
  }

  testWidgets('helper Requests card omits midnight and keeps an evening time '
      'in Russian at phone width', (tester) async {
    await usePhoneSurface(tester);
    final year = DateTime.now().year;

    Future<void> pumpCard(DateTime deadline) async {
      late AttentionReceipt receipt;
      await tester.runAsync(() async {
        receipt = await mapped(_deadlineWire(deadline));
      });
      await tester.pumpWidget(
        _wrap(
          const Locale('ru'),
          AttentionMiniCard(
            receipt: receipt,
            actor: _anna,
            requestTitle: 'Parent request',
          ),
          size: kPhoneSurface,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await pumpCard(DateTime(year, 11, 21, 18));
    expect(find.text('Anna: новый срок — 21 ноября, 18:00'), findsOneWidget);
    await pumpCard(DateTime(year, 11, 29));
    const expected = 'Anna: новый срок — 29 ноября';
    final line = find.textContaining(expected);
    expect(line, findsOneWidget);
    expect(tester.widget<Text>(line).data, expected);
    expect(find.textContaining('00:00', findRichText: true), findsNothing);
  });

  group('request timeline sheet rows', () {
    late _Accounts accounts;
    late AttentionCase attention;
    late TestRealtimeSyncPort realtimePort;

    setUp(() {
      accounts = _Accounts();
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      attention = buildAttentionCase(
        repository: repository,
        accounts: accounts,
        realtimeSyncCase: realtime.case_,
        blockCase: noopBlockCase(),
        feedSessions: FeedSessionRegistry(),
        logger: Logger('linked-request-and-post-row-copy'),
      );
      GetIt.I.registerSingleton<AttentionCase>(attention);
    });

    tearDown(() async {
      await GetIt.I.reset();
      await attention.dispose();
      await accounts.close();
      await realtimePort.dispose();
    });

    Future<void> pumpSheet(
      WidgetTester tester,
      Map<String, dynamic> wire, {
      Locale locale = const Locale('en'),
    }) async {
      remote.items = [wire];
      await tester.pumpWidget(
        _wrap(locale, const RequestAttentionTimelineSheet(beaconId: _beaconId)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Request timeline omits the midnight deadline time in Russian',
      (
        tester,
      ) async {
        ensureNoopAttentionActorProfilesRegistered();
        await usePhoneSurface(tester);
        remote.items = [_deadlineWire(DateTime(DateTime.now().year, 11, 29))];
        await tester.pumpWidget(
          _wrap(
            const Locale('ru'),
            const RequestAttentionTimelineSheet(beaconId: _beaconId),
            size: kPhoneSurface,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        const expected = 'Anna: новый срок — 29 ноября';
        final line = find.textContaining(expected);
        expect(line, findsOneWidget);
        expect(tester.widget<Text>(line).data, expected);
        expect(find.textContaining('00:00', findRichText: true), findsNothing);
      },
    );

    testWidgets('a linked-request status row names the related Request (EN)', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        _wire(
          key: 'beacon_hierarchy_status_changed',
          payload: _linkedPayload(),
          relatedBeaconTitle: 'Fix the roof',
        ),
      );
      expect(find.text('Linked request «Fix the roof» was closed'), findsOne);
    });

    testWidgets('a linked-request status row names the related Request (RU)', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        _wire(
          key: 'beacon_hierarchy_status_changed',
          payload: _linkedPayload(),
          relatedBeaconTitle: 'Fix the roof',
        ),
        locale: const Locale('ru'),
      );
      expect(find.text('Связанный запрос «Fix the roof» закрыт'), findsOne);
    });

    for (final unreadable in <String?>[null, '']) {
      for (final (locale, line) in [
        (const Locale('en'), 'A linked request was closed'),
        (const Locale('ru'), 'Связанный запрос закрыт'),
      ]) {
        testWidgets(
          'an unreadable related Request (${unreadable == null ? 'null' : 'empty'}'
          ') reads "$line" without empty quotes (${locale.languageCode})',
          (tester) async {
            await pumpSheet(
              tester,
              _wire(
                key: 'beacon_hierarchy_status_changed',
                payload: _linkedPayload(),
                relatedBeaconTitle: unreadable,
              ),
              locale: locale,
            );
            expect(find.text(line), findsOne);
            expect(find.textContaining('«»'), findsNothing);
          },
        );
      }
    }

    for (final (locale, pattern) in [
      (const Locale('en'), RegExp(r'Expires in \d+ h')),
      (const Locale('ru'), RegExp(r'Исчезнет через \d+ ч')),
    ]) {
      testWidgets(
        'an already expired Post row shows no countdown (${locale.languageCode})',
        (tester) async {
          await pumpSheet(
            tester,
            _wire(
              key: 'post_expiring_soon',
              payload: _expiringPayload(
                DateTime.now().subtract(const Duration(hours: 2)),
              ),
              beaconKind: 1,
              postRootExcerpt: 'Free apples',
            ),
            locale: locale,
          );
          expect(find.byType(RequestAttentionTimelineSheet), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (w) => w is Text && pattern.hasMatch(w.data ?? ''),
            ),
            findsNothing,
          );
        },
      );
    }
  });

  group('Post rows in the Updates/Activity tile', () {
    Future<void> pumpTile(
      WidgetTester tester,
      Map<String, dynamic> wire, {
      Locale locale = const Locale('en'),
    }) async {
      final receipt = await mapped(wire);
      await tester.pumpWidget(
        _wrap(
          locale,
          UpdatesFeedTile(
            receipt: receipt,
            onTap: () {},
            onMarkSeen: () {},
            onMarkUnseen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool hasText(String needle) => find
        .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(needle))
        .evaluate()
        .isNotEmpty;

    testWidgets('a reply row labels a text-less Post with its author, not '
        'the replier', (tester) async {
      await pumpTile(
        tester,
        _wire(
          key: 'post_first_response',
          payload: _replyPayload(),
          beaconKind: 1,
          postRootExcerpt: '',
          beaconAuthorName: 'Alice',
        ),
      );
      expect(find.text('Bob replied to your post'), findsOne);
      expect(hasText('Post · Alice'), isTrue);
      expect(hasText('Post · Bob'), isFalse);
    });

    testWidgets('a reply row labels a text-less Post with its author (RU)', (
      tester,
    ) async {
      await pumpTile(
        tester,
        _wire(
          key: 'post_first_response',
          payload: _replyPayload(),
          beaconKind: 1,
          postRootExcerpt: '',
          beaconAuthorName: 'Alice',
        ),
        locale: const Locale('ru'),
      );
      expect(hasText('Пост · Alice'), isTrue);
      expect(hasText('Пост · Bob'), isFalse);
    });

    testWidgets('a reply row never names the replier as the Post author', (
      tester,
    ) async {
      await pumpTile(
        tester,
        _wire(
          key: 'post_first_response',
          payload: _replyPayload(),
          beaconKind: 1,
          postRootExcerpt: '',
        ),
      );
      expect(find.text('Bob replied to your post'), findsOne);
      expect(hasText('Post · Bob'), isFalse);
    });

    for (final (locale, needle) in [
      (const Locale('en'), 'Expires in'),
      (const Locale('ru'), 'Исчезнет через'),
    ]) {
      testWidgets(
        'an expired Post row shows no countdown (${locale.languageCode})',
        (tester) async {
          await pumpTile(
            tester,
            _wire(
              key: 'post_expiring_soon',
              payload: _expiringPayload(
                DateTime.now().subtract(const Duration(hours: 2)),
              ),
              beaconKind: 1,
              postRootExcerpt: 'Free apples',
            ),
            locale: locale,
          );
          final l10n = locale.languageCode == 'ru' ? L10nRu() : L10nEn();
          expect(
            find.text(l10n.updatesFallbackTitlePostExpiringSoon),
            findsOneWidget,
            reason: 'the row itself rendered',
          );
          expect(hasText(needle), isFalse);
        },
      );
    }
  });

  group('Post expiry countdown rounds up like the server', () {
    final en = L10nEn();
    final ru = L10nRu();

    UpdatesFeedRowCopy expiring(L10n l10n, Duration left) =>
        resolveUpdatesFeedRowCopy(
          title: 'Your post expires soon',
          body: '',
          presentationKey: 'post_expiring_soon',
          presentationPayloadJson: jsonEncode(
            _expiringPayload(DateTime.now().add(left)),
          ),
          l10n: l10n,
          isPost: true,
          postRootExcerpt: 'Free apples',
        );

    test('90 minutes left reads as 2 h', () {
      expect(
        expiring(en, const Duration(minutes: 90)).body,
        startsWith('Expires in 2 h. Turn it into a request to keep it going'),
      );
      expect(
        expiring(ru, const Duration(minutes: 90)).body,
        startsWith('Исчезнет через 2 ч'),
      );
    });

    test('30 minutes left reads as 1 h', () {
      expect(
        expiring(en, const Duration(minutes: 30)).body,
        startsWith('Expires in 1 h'),
      );
    });

    test(
      'a text-less Post is labelled with its author, as the server does',
      () {
        for (final (l10n, locale) in [(en, 'en'), (ru, 'ru')]) {
          final arb =
              jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
                  as Map<String, dynamic>;
          final fromArb = (arb['updatesPostLabelByAuthor']! as String)
              .replaceAll('{author}', 'Alice');
          expect(postRowLabel(l10n, '', author: 'Alice'), fromArb);
        }
        expect(postRowLabel(en, '', author: 'Alice'), 'Post · Alice');
        expect(postRowLabel(ru, '', author: 'Alice'), 'Пост · Alice');
      },
    );
  });
}
