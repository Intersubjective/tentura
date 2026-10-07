import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

void main() {
  group('domain layout geometry records', () {
    test('LPoint is a structural (x, y) record', () {
      const LPoint a = (x: 1.5, y: -2);
      const LPoint b = (x: 1.5, y: -2);

      expect(a, b);
      expect(a.x, 1.5);
      expect(a.y, -2);
      expect(a, isNot((x: 1.5, y: 2)));
    });

    test('LSize is a structural (w, h) record', () {
      const LSize a = (w: 320, h: 480.5);
      const LSize b = (w: 320, h: 480.5);

      expect(a, b);
      expect(a.w, 320);
      expect(a.h, 480.5);
      expect(a, isNot((w: 480.5, h: 320)));
    });

    test('LPoint and LSize are usable as map values and set members', () {
      final positions = <String, LPoint>{'a': (x: 1, y: 2)};
      final sizes = <LSize>{(w: 1, h: 2), (w: 1, h: 2)};

      expect(positions['a'], (x: 1.0, y: 2.0));
      expect(sizes, hasLength(1));
    });

    test('LRect is a structural (left, top, right, bottom) record', () {
      const LRect a = (left: 10, top: 20, right: 110, bottom: 70);
      const LRect b = (left: 10, top: 20, right: 110, bottom: 70);

      expect(a, b);
      expect(a.left, 10);
      expect(a.top, 20);
      expect(a.right, 110);
      expect(a.bottom, 70);
      expect(a, isNot((left: 10, top: 20, right: 110, bottom: 71)));
    });

    test('lSizeCenter is the midpoint of a size anchored at the origin', () {
      const LSize size = (w: 4096, h: 300);

      expect(lSizeCenter(size), (x: 2048.0, y: 150.0));
    });

    test('lRectCenter is the midpoint of the rect edges', () {
      const LRect rect = (left: 10, top: 20, right: 110, bottom: 70);

      expect(lRectCenter(rect), (x: 60.0, y: 45.0));
    });

    test('lRectSize is the width and height spanned by the rect', () {
      const LRect rect = (left: 10, top: 20, right: 110, bottom: 70);

      expect(lRectSize(rect), (w: 100.0, h: 50.0));
    });
  });
}
