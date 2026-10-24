import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

/// #710 — `Beacon.unansweredHelpOfferCount` drives the My Work card's
/// "Review N offers" line and its "Review offers" button. A backup offer
/// (`offer_kind` 1) kept as standby stays active with no coordination row, so
/// it must not be counted; the Request page already counts only ordinary
/// offers (`offerKind == 0`) as waiting for review.
void main() {
  late String where;

  setUpAll(() {
    final doc = stripGqlComments(
      File('lib/data/gql/beacon_model.graphql').readAsStringSync(),
    );
    final match = RegExp(
      r'unanswered_help_offers:\s*help_offers_aggregate\(\s*where:\s*\{(.*?)\}\s*\)\s*\{\s*aggregate',
      dotAll: true,
    ).firstMatch(doc);
    expect(match, isNotNull, reason: 'unanswered_help_offers is missing');
    where = match!.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
  });

  test('counts only ordinary offers, not backup offers', () {
    expect(where, contains('offer_kind: { _eq: 0 }'));
  });

  test('counts active offers the author has not answered', () {
    expect(where, contains('status: { _eq: 0 }'));
    expect(where, contains('_not: { coordination: {} }'));
  });
}
