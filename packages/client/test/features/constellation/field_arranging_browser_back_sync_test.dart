import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/util/field_arranging_browser_back_sync.dart';

void main() {
  group('FieldArrangingBrowserBackSync (#1062)', () {
    late FieldArrangingBrowserBackSync sync;

    setUp(() {
      sync = FieldArrangingBrowserBackSync(
        pushState: () {},
        back: () {},
        replaceState: () {},
      );
    });

    test('user dismiss pops the sentinel with history.back()', () {
      sync.sync(arranging: true, onPopWhileArranging: () {});
      expect(sync.sentinelPushed, isTrue);

      sync.sync(arranging: false, onPopWhileArranging: () {});
      expect(sync.backInvocationCount, 1);
      expect(sync.replaceStateInvocationCount, 0);
      expect(sync.sentinelPushed, isFalse);
    });

    test('navigation exit replaces the sentinel without history.back()', () {
      sync
        ..sync(arranging: true, onPopWhileArranging: () {})
        ..onExitForNavigation()
        ..sync(arranging: false, onPopWhileArranging: () {});

      expect(sync.backInvocationCount, 0);
      expect(sync.replaceStateInvocationCount, 1);
      expect(sync.sentinelPushed, isFalse);
    });

    test('browser back while arranging only exits the mode', () {
      var arrangeExitCount = 0;
      sync.sync(
        arranging: true,
        onPopWhileArranging: () => arrangeExitCount++,
      );
      sync.onPopState();
      expect(arrangeExitCount, 1);
      expect(sync.sentinelPushed, isFalse);
      expect(sync.backInvocationCount, 0);
    });

    test('suppressed pop after programmatic back is ignored once', () {
      var arrangeExitCount = 0;
      sync
        ..sync(
          arranging: true,
          onPopWhileArranging: () => arrangeExitCount++,
        )
        ..sync(
          arranging: false,
          onPopWhileArranging: () => arrangeExitCount++,
        );
      expect(sync.backInvocationCount, 1);
      sync.onPopState();
      expect(arrangeExitCount, 0, reason: 'synthetic pop from history.back()');
    });
  });
}
