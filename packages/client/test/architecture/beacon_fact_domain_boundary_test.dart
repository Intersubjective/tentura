import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tentura-617.21: the new fact-history domain files must stay pure domain —
/// no Flutter, no data/ui layer imports, no generated GraphQL (`_g/`).
void main() {
  test(
    'new beacon fact domain files do not import flutter, data, ui or _g',
    () {
      final forbidden = RegExp(r'package:flutter|/data/|/ui/|_g/');
      final newDomainFiles = [
        'lib/domain/entity/beacon_fact_history_entry.dart',
        'lib/domain/entity/quoted_fact.dart',
        'lib/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart',
      ];

      for (final path in newDomainFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path must exist');
        final source = file.readAsStringSync();
        expect(
          forbidden.hasMatch(source),
          isFalse,
          reason: '$path must not import flutter, data, ui or generated _g/',
        );
      }
    },
  );
}
