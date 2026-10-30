@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('W3: PollingModel GraphQL fragment is not in lib', () {
    expect(
      File('lib/data/gql/polling_model.graphql').existsSync(),
      isFalse,
    );
    final libGql = Directory('lib/data/gql');
    for (final entity in libGql.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.graphql')) {
        continue;
      }
      final text = entity.readAsStringSync();
      expect(text.contains('fragment PollingModel'), isFalse);
    }
  });
}
