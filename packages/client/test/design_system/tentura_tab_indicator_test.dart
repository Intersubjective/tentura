import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  group('TenturaTabIndicator', () {
    test('resolve maps dot to error and halo to surface (light)', () {
      final scheme = TenturaTheme.light().colorScheme;
      final style = TenturaTabIndicator.resolve(Brightness.light);

      expect(style.dot, scheme.error);
      expect(style.halo, scheme.surface);
    });

    test('resolve maps dot to error and halo to surface (dark)', () {
      final scheme = TenturaTheme.dark().colorScheme;
      final style = TenturaTabIndicator.resolve(Brightness.dark);

      expect(style.dot, scheme.error);
      expect(style.halo, scheme.surface);
    });

    test('resolve memoizes per brightness', () {
      final lightA = TenturaTabIndicator.resolve(Brightness.light);
      final lightB = TenturaTabIndicator.resolve(Brightness.light);
      final darkA = TenturaTabIndicator.resolve(Brightness.dark);
      final darkB = TenturaTabIndicator.resolve(Brightness.dark);

      expect(identical(lightA, lightB), isTrue);
      expect(identical(darkA, darkB), isTrue);
      expect(identical(lightA, darkA), isFalse);
    });

    test('exported from design-system barrel', () {
      expect(TenturaTabIndicatorStyle, isNotNull);
      expect(TenturaTabIndicator, isNotNull);
    });
  });
}
