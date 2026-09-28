import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/browse_deep_link.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';

void main() {
  test('profile link keeps its list-detail entry', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse(
        '$kPathProfileView/U1?$kQueryProfileEntry=$kProfileEntryPeople',
      ),
    )!;
    final route = stack.detail as ProfileViewRoute;
    expect(route.args?.id, 'U1');
    expect(route.args?.entry, kProfileEntryPeople);
  });

  test('profile link without entry has none', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse('$kPathProfileView/U1'),
    )!;
    expect((stack.detail as ProfileViewRoute).args?.entry, isNull);
  });
}
