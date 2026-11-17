@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The updates-event contract declares the two «together» receipt types
/// with their recipient predicates.
void main() {
  final file = [
    File('../../docs/contracts/updates-event-contract.json'),
    File('docs/contracts/updates-event-contract.json'),
  ].firstWhere((f) => f.existsSync());
  final contract = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final classifications = (contract['eventClassifications'] as List)
      .cast<Map<String, dynamic>>();

  for (final (type, predicate) in [
    ('batonPartnerAsked', 'reason:batonPartner'),
    ('batonPartnerAnswered', 'reason:batonCandidate'),
  ]) {
    test('$type is classified for $predicate', () {
      final row = classifications
          .where((r) => r['eventType'] == type)
          .toList();
      expect(row, hasLength(1));
      final variants = (row.single['variants'] as List)
          .cast<Map<String, dynamic>>();
      expect(variants.map((v) => v['recipientPredicate']), contains(predicate));
    });
  }
}
