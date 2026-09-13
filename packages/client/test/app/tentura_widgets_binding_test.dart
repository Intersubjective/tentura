import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/tentura_widgets_binding.dart';

void main() {
  group('shouldSkipUnlaidOutRootChildHitTest', () {
    test('skips a RenderBox that has never been laid out', () {
      expect(
        shouldSkipUnlaidOutRootChildHitTest(_NeverLaidOutBox()),
        isTrue,
      );
    });

    test('does not skip a laid-out RenderBox', () {
      final box = _NeverLaidOutBox()
        ..layout(BoxConstraints.tight(Size.square(10)));
      expect(shouldSkipUnlaidOutRootChildHitTest(box), isFalse);
    });

    test('does not skip a missing child', () {
      expect(shouldSkipUnlaidOutRootChildHitTest(null), isFalse);
    });
  });
}

class _NeverLaidOutBox extends RenderBox {
  @override
  void performLayout() {
    size = constraints.biggest;
  }
}
