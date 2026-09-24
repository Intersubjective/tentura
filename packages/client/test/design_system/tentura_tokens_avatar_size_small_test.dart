import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/design_system/tentura_window_class.dart';

void main() {
  group('TenturaTokens.avatarSizeSmall', () {
    for (final (label, preset) in [
      ('light', TenturaTokens.light),
      ('dark', TenturaTokens.dark),
    ]) {
      test('$label preset exposes avatarSizeSmall as metadataAvatarSize alias', () {
        expect(preset.avatarSizeSmall, preset.metadataAvatarSize);
        expect(preset.avatarSizeSmall, 24);
      });
    }

    test('compact window class uses small metadata avatar diameter', () {
      final tokens = TenturaTokens.light.applyWindowClass(WindowClass.compact);
      expect(tokens.avatarSizeSmall, tokens.metadataAvatarSize);
      expect(tokens.avatarSizeSmall, 24);
    });

    test('regular window class uses small metadata avatar diameter', () {
      final tokens = TenturaTokens.light.applyWindowClass(WindowClass.regular);
      expect(tokens.avatarSizeSmall, tokens.metadataAvatarSize);
      expect(tokens.avatarSizeSmall, 26);
    });

    test('expanded window class uses small metadata avatar diameter', () {
      final tokens = TenturaTokens.light.applyWindowClass(WindowClass.expanded);
      expect(tokens.avatarSizeSmall, tokens.metadataAvatarSize);
      expect(tokens.avatarSizeSmall, 28);
    });

    test('avatarSizeSmall is distinct from medium and tiny avatar tokens', () {
      final tokens = TenturaTokens.light.applyWindowClass(WindowClass.regular);
      expect(tokens.avatarSizeSmall, isNot(tokens.avatarSize));
      expect(tokens.avatarSizeSmall, isNot(tokens.avatarTinySize));
    });

    testWidgets('context.tt exposes avatarSizeSmall through TenturaTheme', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(700, 800)),
            child: TenturaResponsiveScope(
              child: Builder(
                builder: (context) {
                  final tt = context.tt;
                  expect(tt.avatarSizeSmall, tt.metadataAvatarSize);
                  expect(tt.avatarSizeSmall, 26);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
    });
  });
}
