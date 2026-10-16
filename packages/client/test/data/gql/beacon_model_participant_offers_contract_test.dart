import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

/// B055 — `Beacon.helpOfferCount` adds `participant_help_offers` to the active
/// `beacon_help_offer` rows, and a count above zero shows the request as
/// "Coordinating the plan". Withdrawing (or being removed by the author) keeps
/// the participant's status (5 = committed) and only drops `room_access` to 0,
/// so the filter has to look at `room_access` too; otherwise the request
/// never returns to "Looking for helpers" after its only helper withdraws.
void main() {
  late String where;

  setUpAll(() {
    final doc = stripGqlComments(
      File('lib/data/gql/beacon_model.graphql').readAsStringSync(),
    );
    final match = RegExp(
      r'participant_help_offers:\s*beacon_participants\(\s*where:\s*\{(.*?)\}\s*\)\s*\{',
      dotAll: true,
    ).firstMatch(doc);
    expect(match, isNotNull, reason: 'participant_help_offers is missing');
    where = match!.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
  });

  test('counts offered and committed participants', () {
    expect(where, contains('status: { _in: [1, 5] }'));
  });

  test(
    'does not count participants whose room access was revoked or who left',
    () {
      expect(where, contains('room_access: { _nin: [0, 5] }'));
    },
  );
}
