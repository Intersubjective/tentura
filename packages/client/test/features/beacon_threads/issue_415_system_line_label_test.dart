// #415 (QA r8pr3 residual): the room's «Child request created» line was
// one Tab stop, but a screen reader heard its text twice: «Child request
// created. <title> Child request created <title>». Its outer
// `Semantics(label: ...)` named the line and the texts inside it added
// themselves to the same node.
//
// Spec: a system line says its text once, and the tappable one still takes
// the browser focus when Tab lands on it, and a screen reader can still
// activate it (its node keeps the tap action).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_notice.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../features/beacon_create/fake_beacon_ports.dart';
import '../../support/a11y_tab_walk.dart';

const _before = 'Control before';
const _after = 'Control after';
const _title = 'Nested ask';

RoomMessage _message({
  required String body,
  required int systemMessageKind,
  required Map<String, Object?> payload,
}) => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'System actor'),
  body: body,
  createdAt: DateTime.utc(2026),
  systemMessageKind: systemMessageKind,
  systemPayloadJson: jsonEncode(payload),
);

/// Today for the notice: pinned, so the date line does not depend on the
/// calendar the test runs on.
final _today = DateTime(2026, 6);

Future<void> _pump(WidgetTester tester, RoomMessage message) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(onPressed: () {}, child: const Text(_before)),
            BeaconHierarchyNotice(message: message, clock: () => _today),
            ElevatedButton(onPressed: () {}, child: const Text(_after)),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Labels of the engine-visible nodes that say [text] at least once.
List<String> _labelsSaying(String text) => find.semantics
    .byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          node.getSemanticsData().label.contains(text),
    )
    .evaluate()
    .map((node) => node.getSemanticsData().label)
    .toList();

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;

/// Whether the one engine-visible node that says [text] can be activated.
bool _sayingNodeHasTap(String text) => find.semantics
    .byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          node.getSemanticsData().label.contains(text),
    )
    .evaluate()
    .single
    .getSemanticsData()
    .hasAction(SemanticsAction.tap);

void main() {
  final l10n = L10nEn();

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets(
    '#415 Child request created line: says its text once, one Tab stop',
    (tester) async {
      final handle = tester.ensureSemantics();
      final port = FakeBeaconHierarchyRepositoryPort()
        ..childPreviews['child-1'] = BeaconHierarchySummary(
          beaconId: 'child-1',
          title: _title,
          owner: const BeaconHierarchyOwnerSummary(
            id: 'author-1',
            displayName: 'Alice',
          ),
          status: BeaconStatus.open,
          publishedAt: DateTime.utc(2026),
          isTombstone: false,
        );
      GetIt.I.registerSingleton<BeaconHierarchyCase>(
        buildBeaconHierarchyCaseForTest(
          port,
          createCase: BeaconCreateCase(
            FakeBeaconWritePort(),
            FakeBeaconImagePort(),
          ),
          beacons: FakeBeaconWritePort(),
          commandStore: InMemoryBeaconChildCommandStore(),
        ),
      );
      await _pump(
        tester,
        _message(
          body: '',
          systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
          payload: {
            'version': 1,
            'kind': 'childCreated',
            'childBeaconId': 'child-1',
          },
        ),
      );
      expect(
        find.text(_title),
        findsOneWidget,
        reason: 'precondition: the child title is loaded',
      );

      final line = l10n.beaconHierarchyNoticeChildCreated;
      final labels = _labelsSaying(line);
      expect(labels, hasLength(1), reason: '$labels');
      expect(_count(labels.single, line), 1, reason: labels.single);
      expect(_count(labels.single, _title), 1, reason: labels.single);
      expect(
        _sayingNodeHasTap(line),
        isTrue,
        reason: 'a screen reader can still open the child request',
      );

      final stops = await walkTabStops(tester, before: _before, after: _after);
      // The line, then after.
      expect(stops, hasLength(2), reason: '$stops');
      expect(stops.first, contains(line), reason: '$stops');
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('#415 Post bud line: says its text once and keeps its tap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      _message(
        body: '',
        systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        payload: {
          'version': 1,
          'kind': 'childCreated',
          'childBeaconId': 'child-1',
          'title': _title,
          'invitedCount': 2,
        },
      ),
    );

    final labels = _labelsSaying(_title);
    expect(labels, hasLength(1), reason: '$labels');
    expect(_count(labels.single, _title), 1, reason: labels.single);
    expect(
      _sayingNodeHasTap(_title),
      isTrue,
      reason: 'a screen reader can still open the child request',
    );
    handle.dispose();
  });

  testWidgets('#415 lifecycle line: says its text once', (tester) async {
    final handle = tester.ensureSemantics();
    final year = _today.year;
    const dated = 'A child request was cancelled on Feb 2';
    await _pump(
      tester,
      _message(
        body: 'A child request was cancelled on $year-02-02',
        systemMessageKind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
        payload: {
          'version': 1,
          'kind': 'hierarchyLifecycle',
          'eventId': 'e2',
          'targetBeaconId': 'b1',
          'direction': 'child',
          'toStatus': 'cancelled',
          'occurredAt': '$year-02-02T12:00:00Z',
          'sourceDeleted': false,
        },
      ),
    );

    final labels = _labelsSaying(dated);
    expect(labels, hasLength(1), reason: '$labels');
    expect(_count(labels.single, dated), 1, reason: labels.single);
    handle.dispose();
  });
}
