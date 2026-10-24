// Issue #501: a reload or deep link of a Post's forwards graph keeps the
// kind from the URL, so the title can name the post before it loads.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/browse_deep_link.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';

void main() {
  test('forwards graph link of a post carries the post kind', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse('$kPathForwardsGraph/B1?$kQueryForwardsGraphKind=post'),
    )!;
    final route = stack.detail as ForwardsGraphRoute;
    expect(route.args?.focus, 'B1');
    expect(route.args?.kind, 'post');
  });

  test('forwards graph link without a kind has none', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse('$kPathForwardsGraph/B1'),
    )!;
    expect((stack.detail as ForwardsGraphRoute).args?.kind, isNull);
  });
}
