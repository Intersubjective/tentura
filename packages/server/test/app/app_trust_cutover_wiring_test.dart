import 'dart:io';

import 'package:test/test.dart';

void main() {
  final app = File('lib/app/app.dart').readAsStringSync();

  test('app.dart runs TrustCutoverCase.runIfPending after the pgmer2 upgrade '
      'and before workers start', () {
    expect(app, contains('getIt<TrustCutoverCase>().runIfPending()'));
    final upgrade = app.indexOf('ALTER EXTENSION pgmer2 UPDATE');
    final cutover = app.indexOf('runIfPending()');
    final workers = app.indexOf('spawnTaskWorker');
    expect(upgrade, greaterThanOrEqualTo(0));
    expect(cutover, greaterThan(upgrade));
    expect(workers, greaterThan(cutover));
  });

  test('graph init only runs once cutover is done', () {
    final start = app.indexOf('Future<void> _uploadGraph');
    expect(start, greaterThanOrEqualTo(0));
    final body = app.substring(start);
    final tryAt = body.indexOf('try {');
    final edgelist = body.indexOf('mr_edgelist()');
    final init = body.indexOf('meritrank_init()');
    expect(tryAt, greaterThanOrEqualTo(0));
    expect(edgelist, greaterThan(tryAt), reason: 'empty-graph check is kept');
    expect(init, greaterThan(edgelist));
    // The only graph init in the file is the one inside _uploadGraph.
    expect('meritrank_init()'.allMatches(app), hasLength(1));
    // The done-check is the first thing in the try block, so it guards the
    // empty-graph check and the init that follows it, and it early-returns.
    final head = body.substring(tryAt + 'try {'.length, edgelist);
    final guard = RegExp(
      r'^\s*(//[^\n]*\n\s*)*(final\s+\w+\s*=\s*)?(await\s+)?'
      r'[^;{]*(isDone|trust_cutover_state)[^;]*;'
      r'[\s\S]*?\breturn\b',
    ).firstMatch(head);
    expect(guard, isNotNull, reason: 'done-guard first, with early return');
    expect(
      head.substring(guard!.end),
      isNot(contains('meritrank_init')),
    );
  });
}
