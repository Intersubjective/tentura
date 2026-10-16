// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/platform/path_deep_link_policy.dart';

void main() {
  group('hashUrlForPathDeepLink', () {
    test('profile share link becomes its hash route', () {
      expect(
        hashUrlForPathDeepLink(pathname: '/profile/view/U325f01f7d5b8'),
        '/#/profile/view/U325f01f7d5b8',
      );
    });

    test('request link keeps its query', () {
      expect(
        hashUrlForPathDeepLink(
          pathname: '/beacon/view/Bd0c1a2b3c4d5',
          search: '?tab=people',
        ),
        '/#/beacon/view/Bd0c1a2b3c4d5?tab=people',
      );
    });

    test('an empty fragment does not block the rewrite', () {
      expect(
        hashUrlForPathDeepLink(
          pathname: '/profile/view/U325f01f7d5b8',
          hash: '#/',
        ),
        '/#/profile/view/U325f01f7d5b8',
      );
    });

    test('an existing hash route wins', () {
      expect(
        hashUrlForPathDeepLink(
          pathname: '/profile/view/U325f01f7d5b8',
          hash: '#/home/work',
        ),
        isNull,
      );
    });

    test('other paths are left alone', () {
      for (final path in ['/', '/index.html', '/profile/view/', '/recover']) {
        expect(hashUrlForPathDeepLink(pathname: path), isNull, reason: path);
      }
    });
  });
}
