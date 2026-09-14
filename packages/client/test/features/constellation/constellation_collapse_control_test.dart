import 'package:flutter_test/flutter_test.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  test('expandedExtraCountByAuthor tracks collapse control (UI-13)', () async {
    final cubit = await loadReferenceCubit();
    addTearDown(cubit.close);

    expect(cubit.expandedExtraCountByAuthor, isEmpty);
    expect(cubit.overflowHiddenCountByAuthor['ego'], 3);

    cubit.toggleSatelliteOverflow('ego');
    expect(cubit.isSatelliteOverflowExpanded('ego'), isTrue);
    expect(cubit.expandedExtraCountByAuthor['ego'], greaterThan(0));

    cubit.toggleSatelliteOverflow('ego');
    expect(cubit.isSatelliteOverflowExpanded('ego'), isFalse);
    expect(cubit.expandedExtraCountByAuthor, isEmpty);
    expect(cubit.overflowHiddenCountByAuthor['ego'], 3);
  });
}
