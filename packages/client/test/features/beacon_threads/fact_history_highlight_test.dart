// The fact history sheet opened at a revision (plan §6.1, «See the copied
// version»): history pages hold 50 revisions, newest first; the sheet loads
// pages until the revision appears, at most 10, and marks that row; the mark
// is exposed as the row's selected state, so assistive technology perceives
// it too. Beyond 10 pages it shows the history from the top with no row
// marked. Rows are scrolled into view before they are checked, so the
// sheet may build its list lazily.
//
// `highlightSeq` is the parameter the plan names for showFactHistorySheet;
// until it exists this file does not compile.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';

import 'fact_origin_test_support.dart';

const _screen = Size(400, 900);

Future<FakeOriginFactCardRepository> _openAt(
  WidgetTester tester, {
  required int historyLength,
  required int highlightSeq,
}) async {
  final repo = FakeOriginFactCardRepository(historyLength: historyLength);
  await pumpOpener(
    tester,
    size: _screen,
    open: (ctx) => unawaited(
      showFactHistorySheet(
        ctx,
        beaconId: kSourceBeaconId,
        factCardId: kSourceFactId,
        baseRevisionSeq: historyLength,
        canMutate: false,
        repository: repo,
        highlightSeq: highlightSeq,
      ),
    ),
  );
  expect(find.byType(FactHistorySheet), findsOneWidget);
  return repo;
}

void main() {
  testWidgets('a revision on page 3 loads exactly 3 pages and only its row '
      'is marked', (tester) async {
    final semantics = tester.ensureSemantics();
    // 200 revisions: page 3 holds 100..51.
    final repo = await _openAt(tester, historyLength: 200, highlightSeq: 80);

    expect(repo.pagesRequested, 3);
    await scrollToRevision(tester, 80);
    await tester.pumpAndSettle();
    expect(selectedRevisions(tester), {80});
    semantics.dispose();
  });

  testWidgets('a revision beyond the first 10 pages stops after exactly 10 '
      'pages, starts at the newest revision and marks no row', (tester) async {
    final semantics = tester.ensureSemantics();
    // 600 revisions: the first 10 pages hold 600..101; revision 10 is not
    // among them.
    final repo = await _openAt(tester, historyLength: 600, highlightSeq: 10);

    expect(repo.pagesRequested, 10);
    // Opened at the top: the newest revision's row is on screen.
    final newest = find
        .textContaining(revisionActor(600), findRichText: true)
        .first;
    expect(newest, findsOneWidget);
    final top = tester.getRect(newest);
    expect(top.top, greaterThanOrEqualTo(0));
    expect(top.bottom, lessThanOrEqualTo(_screen.height));
    expect(selectedRevisions(tester), isEmpty);
    // Further down nothing is marked either.
    await scrollToRevision(tester, 300);
    await tester.pumpAndSettle();
    expect(selectedRevisions(tester), isEmpty);
    semantics.dispose();
  });
}
