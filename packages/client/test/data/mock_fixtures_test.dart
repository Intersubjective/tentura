import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/mock/data/fixtures.dart';

void main() {
  test('kEmptyGraphqlMapFixture is wired', () {
    expect(kEmptyGraphqlMapFixture, isEmpty);
  });
}
