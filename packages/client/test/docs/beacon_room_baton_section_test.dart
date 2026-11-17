@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test("beacon_room.md «Who'll take it?» covers together-with and partner privacy",
      () {
    final doc = File('../../docs/features/beacon_room.md').readAsStringSync();
    final start = doc.indexOf("## Who'll take it?");
    final end = doc.indexOf('## Read receipts');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final section = doc.substring(start, end);
    expect(section, contains('Together with'));
    expect(section, contains('partner-privacy rule'));
    expect(section, isNot(contains('on their own non-system message')));
  });
}
