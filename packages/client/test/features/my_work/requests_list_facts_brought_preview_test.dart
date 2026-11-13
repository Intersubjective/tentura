// The Requests card's «latest» line for a thread whose last message brought
// facts in from another Request or Post (preview kind factsBrought = 13): a
// single fact reads as its text, a group (no text) as «brought N facts».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_threads_list.data.gql.dart';
import 'package:tentura/features/beacon_threads/data/model/request_thread_model.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_latest_message_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _now = DateTime.utc(2026, 10, 14, 12);

MyWorkCardViewModel _vm(ThreadMessagePreview? preview) => MyWorkCardViewModel(
  beaconId: 'B1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'B1', title: 'Moving day'),
  roomLatestMessageAuthorId: 'u-nina',
  roomLatestMessageAuthorName: 'Nina',
  roomLatestMessageAt: _now.subtract(const Duration(minutes: 1)),
).withLatestThreadPreview(preview);

Future<void> _pump(
  WidgetTester tester,
  MyWorkCardViewModel vm, {
  Locale locale = const Locale('en'),
  Size size = const Size(800, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: MyWorkLatestMessageLine(
            vm: vm,
            currentUserId: 'u-me',
            now: _now.toLocal(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _shown(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? '',
].join('\n');

ThreadMessagePreview _previewOverTransport({
  required String? factTitle,
  required int? factCount,
}) {
  final data = GBeaconThreadsListData.fromJson({
    '__typename': 'query_root',
    'beaconThreads': [
      {
        '__typename': 'v2_BeaconThreadRow',
        'threadId': 'general',
        'threadKind': 'general',
        'unreadCount': 1,
        'messageCount': 2,
        'lastSeenAt': null,
        'lastMessageAt': '2026-10-14T11:59:00.000Z',
        'lastMessageAuthorId': 'u-nina',
        'lastMessagePreview': {
          '__typename': 'v2_ThreadMessagePreview',
          'kind': 13,
          'excerpt': null,
          'hasAttachment': false,
          'joinedUserId': null,
          'admissionReason': null,
          'linkedItemId': null,
          'linkedEventKind': null,
          'itemKind': null,
          'itemTitle': null,
          'pollTitle': null,
          'factTitle': factTitle,
          'factCount': factCount,
          'factVisibility': null,
        },
      },
    ],
  })!;
  return RequestThreadRowModel(
    data.beaconThreads!.single,
  ).toEntity().lastMessagePreview!;
}

void main() {
  group('Requests card latest line, facts brought', () {
    testWidgets('one fact shows its text', (tester) async {
      await _pump(
        tester,
        _vm(
          const ThreadMessagePreview(
            kind: ThreadMessagePreviewKind.factsBrought,
            factTitle: 'Gate code 4411',
            factCount: 1,
          ),
        ),
      );
      expect(find.textContaining('Gate code 4411'), findsOneWidget);
    });

    testWidgets('a group without text reads «brought 3 facts»', (tester) async {
      await _pump(
        tester,
        _vm(
          const ThreadMessagePreview(
            kind: ThreadMessagePreviewKind.factsBrought,
            factCount: 3,
          ),
        ),
      );
      expect(find.textContaining('Nina: brought 3 facts'), findsOneWidget);
    });

    testWidgets('a preview of another kind leaves the line alone', (
      tester,
    ) async {
      await _pump(
        tester,
        _vm(const ThreadMessagePreview(kind: ThreadMessagePreviewKind.text)),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a beaconThreads row with kind 13, no title, count 3 '
        'reaches the card as «brought 3 facts»', (tester) async {
      await _pump(
        tester,
        _vm(_previewOverTransport(factTitle: null, factCount: 3)),
      );
      expect(find.textContaining('brought 3 facts'), findsOneWidget);
    });

    testWidgets('a beaconThreads row with a title shows the title', (
      tester,
    ) async {
      await _pump(
        tester,
        _vm(_previewOverTransport(factTitle: 'Gate code 4411', factCount: 1)),
      );
      expect(find.textContaining('Gate code 4411'), findsOneWidget);
    });

    group('Russian at 375x667', () {
      const ru = Locale('ru');
      const phone = Size(375, 667);

      for (final (count, word) in [(3, 'факта'), (5, 'фактов'), (21, 'факт')]) {
        testWidgets('$count facts read «$count $word»', (tester) async {
          await _pump(
            tester,
            _vm(
              ThreadMessagePreview(
                kind: ThreadMessagePreviewKind.factsBrought,
                factCount: count,
              ),
            ),
            locale: ru,
            size: phone,
          );
          expect(tester.takeException(), isNull);
          final text = _shown(tester);
          expect(text, contains('принёс(ла) $count $word'));
          expect(text, isNot(contains('brought')));
        });
      }
    });
  });
}
