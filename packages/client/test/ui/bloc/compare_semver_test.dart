import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/bloc/app_update_cubit.dart';

void main() {
  group('compareSemver', () {
    test('compares major.minor.patch numerically', () {
      expect(compareSemver('1.0.0', '1.0.1'), lessThan(0));
      expect(compareSemver('1.2.0', '1.1.9'), greaterThan(0));
      expect(compareSemver('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('returns zero for equal versions', () {
      expect(compareSemver('1.17.0', '1.17.0'), 0);
      expect(compareSemver('v1.17.0', '1.17.0'), 0);
    });

    test('strips leading v and prerelease suffix', () {
      expect(compareSemver('V1.2.3-beta', '1.2.3'), 0);
      expect(compareSemver('1.2.3-rc.1', '1.2.3'), 0);
    });

    test('treats missing patch segments as zero', () {
      expect(compareSemver('1.2', '1.2.0'), 0);
      expect(compareSemver('1', '1.0.0'), 0);
    });

    test('treats non-numeric segments as zero', () {
      expect(compareSemver('1.x.0', '1.0.0'), 0);
    });
  });
}
