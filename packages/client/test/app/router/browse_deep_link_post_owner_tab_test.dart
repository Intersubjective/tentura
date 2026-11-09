import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/browse_deep_link.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';

void main() {
  test('post view deep link opens under Conversations home tab', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse('$kPathPostView/post-42'),
    )!;
    expect(stack.detail.routeName, PostViewRoute.name);
    final spec = HomeTabSpec.forTab(HomeTab.conversations);
    expect(
      stack.home,
      HomeRoute(
        children: [
          spec.shell(children: [spec.rootRoute()]),
        ],
      ),
    );
  });

  test('markBrowseStackDetailColdStart sets is_deep_link on browse detail', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse('$kPathPostView/post-42'),
    )!;
    final marked = markBrowseStackDetailColdStart(stack.detail);
    expect(marked, isA<PostViewRoute>());
    final args = (marked as PostViewRoute).args!;
    expect(args.isDeepLink, 'true');
  });

  test('beacon view deep link stays under Requests home tab', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse('$kPathBeaconView/beacon-9'),
    )!;
    expect(stack.detail.routeName, BeaconViewRoute.name);
    final spec = HomeTabSpec.forTab(HomeTab.work);
    expect(
      stack.home,
      HomeRoute(
        children: [
          spec.shell(children: [spec.rootRoute()]),
        ],
      ),
    );
  });
}
