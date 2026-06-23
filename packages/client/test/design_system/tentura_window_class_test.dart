import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_window_class.dart';

void main() {
  group('windowClassForWidth', () {
    test('compact below 600 logical px', () {
      expect(windowClassForWidth(0), WindowClass.compact);
      expect(windowClassForWidth(599.9), WindowClass.compact);
    });

    test('regular from 600 up to but not including 840', () {
      expect(windowClassForWidth(600), WindowClass.regular);
      expect(windowClassForWidth(839.9), WindowClass.regular);
    });

    test('expanded from 840 and above', () {
      expect(windowClassForWidth(840), WindowClass.expanded);
      expect(windowClassForWidth(1200), WindowClass.expanded);
    });
  });
}
