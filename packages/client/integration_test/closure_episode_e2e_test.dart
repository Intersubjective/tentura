// A25 end-to-end scenarios for episode closure (web integration suite).
//
// Setup goes through two helpers that A25 must add to
// `support/e2e_test_helpers.dart` (backed by a QA server endpoint):
//  * [bootstrapClosureFixture] - author + three helpers with accepted offers
//    on one published request.
//  * [runGraphQlAs] - posts a raw V2 GraphQL document as a given user and
//    returns the decoded `data` map (throws on GraphQL errors).
import 'package:flutter/material.dart' show Card, IconData, Icons, Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

Future<Map<String, dynamic>> _as(
  ClosureFixture f,
  String email,
  String query,
) => runGraphQlAs(email: email, restoreEmail: f.authorEmail, query: query);

Future<int> _epoch(ClosureFixture f, String email) async {
  final data = await _as(
    f,
    email,
    'query { closureState(beaconId: "${f.beaconId}") { epoch } }',
  );
  return (data['closureState'] as Map)['epoch'] as int;
}

Future<Map<String, dynamic>> _result(ClosureFixture f, String email) async {
  final data = await _as(
    f,
    email,
    'query { closureResultForViewer(beaconId: "${f.beaconId}") '
    '{ outcome band draftFlag marks story } }',
  );
  return (data['closureResultForViewer'] as Map).cast<String, dynamic>();
}

Future<void> _closeSupportExpire(WidgetTester tester) async {
  final f = await bootstrapClosureFixture(runId: uniqueRunId('closure-a'));
  final [h1, h2, h3] = f.helperEmails;
  final [id1, id2, id3] = f.helperUserIds;

  await _as(
    f,
    f.authorEmail,
    'mutation { beaconClose(beaconId: "${f.beaconId}") }',
  );
  final epoch = await _epoch(f, f.authorEmail);
  // Author split 70/20/10 across the three helpers (V3 bands).
  await _as(
    f,
    f.authorEmail,
    'mutation { closureSaveAuthorSplit(beaconId: "${f.beaconId}", '
    'expectedEpoch: $epoch, split: [ '
    '{helperId: "$id1", pct: 70}, {helperId: "$id2", pct: 20}, '
    '{helperId: "$id3", pct: 10}]) }',
  );
  // Helper 1 supports helper 3, bookmarks the author, presses Done.
  await _as(
    f,
    h1,
    'mutation { closureToggleSupport(beaconId: "${f.beaconId}", '
    'expectedEpoch: $epoch, on: true, targetId: "$id3") { released } }',
  );
  await _as(
    f,
    h1,
    'mutation { closureSetMark(beaconId: "${f.beaconId}", '
    'expectedEpoch: $epoch, on: true, targetId: "${f.authorUserId}") }',
  );
  await _as(
    f,
    h1,
    'mutation { closureDone(beaconId: "${f.beaconId}", '
    'expectedEpoch: $epoch) }',
  );
  // Helper 2 skips.
  await _as(
    f,
    h2,
    'mutation { closureSkip(beaconId: "${f.beaconId}", '
    'expectedEpoch: $epoch) }',
  );

  await expireClosure(beaconId: f.beaconId);

  // V3 (70/20/10, helper 1 supports helper 3): helper 1 is as if silent,
  // helper 2 (who skipped) is lowered, helper 3 is raised.
  final expectedBand = {
    h1: ('asIfSilent', 'Your share is as if colleagues had stayed silent'),
    h2: ('lowered', 'Colleagues lowered your share'),
    h3: ('raised', 'Colleagues raised your share'),
  };
  for (final MapEntry(key: email, value: (band, _)) in expectedBand.entries) {
    expect(
      (await _result(f, email))['band'],
      band,
      reason: 'server band for $email',
    );
  }
  expect((await _result(f, h1))['marks'], contains(f.authorUserId));

  // Every helper sees the rendered results card with their own band.
  for (final MapEntry(key: email, value: (_, text)) in expectedBand.entries) {
    await logout(tester);
    await loginAs(tester, email);
    await openRequestFromMyWork(tester, requestTitle: f.beaconTitle);
    await pumpUntilVisible(tester, find.text('Results for you'));
    await pumpUntilVisible(tester, find.text(text));
  }
}

Future<void> _reopenKeepsDrafts(WidgetTester tester) async {
  final f = await bootstrapClosureFixture(runId: uniqueRunId('closure-b'));
  final h1 = f.helperEmails.first;
  final [id1, id2, id3] = f.helperUserIds;
  final beacon = f.beaconId;

  await _as(
    f,
    f.authorEmail,
    'mutation { beaconClose(beaconId: "$beacon") }',
  );
  final epoch = await _epoch(f, f.authorEmail);
  // Author drafts: an outcome, a story and a custom split.
  await _as(
    f,
    f.authorEmail,
    'mutation { closureSaveOutcome(beaconId: "$beacon", '
    'expectedEpoch: $epoch, helperId: "$id1", outcome: done) }',
  );
  await _as(
    f,
    f.authorEmail,
    'mutation { closureSaveStory(beaconId: "$beacon", '
    'expectedEpoch: $epoch, body: "draft story") }',
  );
  await _as(
    f,
    f.authorEmail,
    'mutation { closureSaveAuthorSplit(beaconId: "$beacon", '
    'expectedEpoch: $epoch, split: [ '
    '{helperId: "$id1", pct: 70}, {helperId: "$id2", pct: 20}, '
    '{helperId: "$id3", pct: 10}]) }',
  );
  // Helper 1 supports helper 3 and presses Done: a committed version.
  await _as(
    f,
    h1,
    'mutation { closureToggleSupport(beaconId: "$beacon", '
    'expectedEpoch: $epoch, on: true, targetId: "$id3") { released } }',
  );
  await _as(
    f,
    h1,
    'mutation { closureDone(beaconId: "$beacon", expectedEpoch: $epoch) }',
  );
  Future<Map<String, dynamic>> helperState() async =>
      ((await _as(
                f,
                h1,
                'query { closureState(beaconId: "$beacon") '
                '{ epoch mySupport inCalcText } }',
              ))['closureState']
              as Map)
          .cast<String, dynamic>();
  expect((await helperState())['inCalcText'], 'counted');

  await _as(
    f,
    f.authorEmail,
    'mutation { beaconReopen(beaconId: "$beacon", expectedEpoch: $epoch) }',
  );
  await _as(
    f,
    f.authorEmail,
    'mutation { beaconClose(beaconId: "$beacon") }',
  );

  final author =
      ((await _as(
                f,
                f.authorEmail,
                'query { closureState(beaconId: "$beacon") '
                '{ epoch outcomes { helperId outcome } story '
                'split { helperId pct } } }',
              ))['closureState']
              as Map)
          .cast<String, dynamic>();
  expect(author['epoch'], epoch + 1, reason: 'reopen+close is a new epoch');
  expect(
    (author['outcomes'] as List).map(
      (o) => (o as Map).cast<String, dynamic>(),
    ),
    [
      {'helperId': id1, 'outcome': 'done'},
    ],
    reason: 'the saved outcome (with its value) is prefilled',
  );
  expect(author['story'], 'draft story', reason: 'story draft is prefilled');
  expect(
    {
      for (final e in author['split'] as List) (e as Map)['helperId']: e['pct'],
    },
    {id1: 70, id2: 20, id3: 10},
    reason: 'the custom split survives the reopen',
  );

  // Helper 1: the draft support is kept, the committed version is gone.
  final helper = await helperState();
  expect(helper['epoch'], epoch + 1);
  expect(helper['mySupport'], [id3], reason: 'support draft is kept');
  expect(
    helper['inCalcText'],
    'notCounted',
    reason: 'the committed support and Done were removed by the reopen',
  );
}

Future<void> _bookmarkToggle(WidgetTester tester) async {
  final f = await bootstrapClosureFixture(runId: uniqueRunId('closure-c'));
  final h1 = f.helperEmails.first;

  await _as(
    f,
    f.authorEmail,
    'mutation { beaconClose(beaconId: "${f.beaconId}") }',
  );
  await expireClosure(beaconId: f.beaconId);
  // The finalized result exists for the viewer and carries no bookmark yet.
  expect((await _result(f, h1))['marks'], isEmpty);

  await logout(tester);
  await loginAs(tester, h1);
  await openRequestFromMyWork(tester, requestTitle: f.beaconTitle);
  final card = find.ancestor(
    of: find.text('Results for you'),
    matching: find.byType(Card),
  );
  await pumpUntilVisible(tester, card);

  // The bookmark control of the author's row inside the results card.
  final authorRow = find.descendant(
    of: card,
    matching: find.ancestor(
      of: find.text(f.authorName),
      matching: find.byType(Row),
    ),
  );
  Finder icon(IconData d) =>
      find.descendant(of: authorRow, matching: find.byIcon(d));

  Future<void> tapAndExpect({required bool on}) async {
    await tapAndSettle(
      tester,
      icon(on ? Icons.bookmark_border : Icons.bookmark).first,
    );
    await pumpUntilVisible(
      tester,
      icon(on ? Icons.bookmark : Icons.bookmark_border),
    );
    final marks = (await _result(f, h1))['marks'] as List;
    expect(
      marks.contains(f.authorUserId),
      on,
      reason:
          'server result reflects the card after toggling ${on ? 'on' : 'off'}',
    );
  }

  await pumpUntilVisible(tester, icon(Icons.bookmark_border));
  await tapAndExpect(on: true);
  await tapAndExpect(on: false);
  await tapAndExpect(on: true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // One test: the app (GetIt) can be launched only once per page load.
  testWidgets('closure episode: bands, reopen prefill, bookmark toggle', (
    tester,
  ) async {
    await launchApp(app.main);
    await pumpSettleBounded(tester);
    await _closeSupportExpire(tester);
    await _reopenKeepsDrafts(tester);
    await _bookmarkToggle(tester);
  });
}
