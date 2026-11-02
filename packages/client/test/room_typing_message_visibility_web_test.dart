@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

import 'features/beacon_threads/room_typing_message_visibility_test.dart'
    as discussion;

bool _browserExposes(String label) {
  final nodes = web.document.querySelectorAll('flt-semantics');
  for (var index = 0; index < nodes.length; index++) {
    final element = nodes.item(index)! as web.Element;
    if (element.getAttribute('aria-label') == label ||
        element.textContent == label) {
      return true;
    }
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  discussion.runRoomTypingVisibilityTests(
    verifyBrowserSemantics: (tester, label, visible) async {
      // This target must run in a real 375x667 browser, not only a constrained
      // Flutter render surface with a desktop browser MediaQuery underneath.
      expect(web.window.innerWidth, 375);
      expect(web.window.innerHeight, 667);
      for (var frame = 0; frame < 20; frame++) {
        if (_browserExposes(label) == visible) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        _browserExposes(label),
        visible,
        reason:
            'screen readers need the active typing label in the browser accessibility DOM',
      );
    },
  );
}
