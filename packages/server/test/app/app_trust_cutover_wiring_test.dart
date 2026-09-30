import 'dart:io';

import 'package:test/test.dart';

void main() {
  final app = File('lib/app/app.dart').readAsStringSync();
  String read(String path) => File(path).readAsStringSync();

  test('app.dart no longer calls the trust cutoverBackfillIfNeeded', () {
    // Only the attention cutover may keep its own backfill call.
    final calls = RegExp(
      r'getIt<(\w+)>\(\)\s*\.cutoverBackfillIfNeeded\(',
    ).allMatches(app).map((m) => m.group(1)).toList();
    expect(calls, everyElement('AttentionCutoverCase'));
    // No other receiver shape (variable, port, repository) either.
    expect(
      RegExp(r'cutoverBackfillIfNeeded\(').allMatches(app).length,
      calls.length,
    );
  });

  test('trust cutoverBackfillIfNeeded is deleted from repo, port and case', () {
    for (final f in const [
      'lib/data/repository/user_trust_edge_repository.dart',
      'lib/domain/port/user_trust_edge_repository_port.dart',
      'lib/domain/use_case/user_trust_edge_case.dart',
      'lib/data/repository/mock/user_trust_edge_repository_mock.dart',
    ]) {
      expect(read(f), isNot(contains('cutoverBackfillIfNeeded')), reason: f);
    }
  });

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

  test('backfill-only code is gone from UserTrustEdgeRepository', () {
    final repo = read('lib/data/repository/user_trust_edge_repository.dart');
    // The old backfill read every non-zero vote and bumped the MR epoch.
    expect(repo, isNot(contains('FROM vote_user WHERE amount <> 0')));
    expect(repo, isNot(contains('bumpMrEpoch')));
    expect(repo, isNot(contains('hasProjection')));
    expect(repo, isNot(contains('DateTime.timestamp()')));
  });
}
