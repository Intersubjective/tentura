import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/design_system/tentura_window_class.dart';

void main() {
  group('TenturaTokens.applyWindowClass', () {
    test('compact keeps full-width content and compact density', () {
      final tokens = TenturaTokens.light.applyWindowClass(WindowClass.compact);
      expect(tokens.contentMaxWidth, isNull);
      expect(tokens.chatWideWidth, 840);
      expect(tokens.chatColumnMaxWidth, 720);
      expect(tokens.bubbleMinWidth, 160);
      expect(tokens.avatarGutter, 40);
      expect(tokens.bubbleFarGutter, 56);
      expect(tokens.mediaMaxWidth, 520);
      expect(tokens.albumGridGap, 4);
      expect(tokens.avatarSize, 36);
      expect(tokens.bottomNavHeight, 64);
    });

    test('regular constrains content width and increases density', () {
      final tokens = TenturaTokens.light.applyWindowClass(WindowClass.regular);
      expect(tokens.contentMaxWidth, 560);
      expect(tokens.mediaMaxWidth, 520);
      expect(tokens.avatarSize, 40);
      expect(tokens.bottomNavHeight, 72);
    });

    test('expanded uses widest content max width', () {
      final tokens = TenturaTokens.light.applyWindowClass(WindowClass.expanded);
      expect(tokens.contentMaxWidth, 720);
      expect(tokens.mediaMaxWidth, 640);
      expect(tokens.avatarSize, 44);
      expect(tokens.screenHPadding, 24);
    });
  });
}
