import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

/// B056 — People › Trusted reads the viewer's positive `vote_user` rows.
/// Blocking keeps that row on purpose (the trust evidence comes back on
/// unblock; see docs/features/user-block.md, B3), so the list itself has to
/// leave out people hidden from the viewer by a block, the same
/// `hidden_for_viewer` rule the `user` select permission uses.
void main() {
  late String where;

  setUpAll(() {
    final doc = stripGqlComments(
      File(
        'lib/features/friends/data/gql/friends_fetch.graphql',
      ).readAsStringSync(),
    );
    final match = RegExp(
      r'vote_user\(\s*where:\s*\{(.*)\}\s*\)\s*\{',
      dotAll: true,
    ).firstMatch(doc);
    expect(match, isNotNull, reason: 'vote_user query is missing');
    where = match!.group(1)!.replaceAll(RegExp(r'\s+'), '');
  });

  test('lists only people the viewer trusts', () {
    expect(where, contains('amount:{_gt:0}'));
  });

  test('leaves out people hidden from the viewer by a block', () {
    expect(where, contains('hidden_for_viewer:{_eq:false}'));
  });

  test("keeps main's guard against users Hasura hides (tentura-m43h)", () {
    expect(where, contains('id:{_is_null:false}'));
  });
}
