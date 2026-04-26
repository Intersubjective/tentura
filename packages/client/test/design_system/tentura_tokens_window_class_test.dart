import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  group('TenturaTokens.applyWindowClass', () {
    test('compact matches TenturaSpacing density', () {
      final t = TenturaTokens.light.applyWindowClass(WindowClass.compact);
      expect(t.cardPadding, TenturaSpacing.cardPaddingAll);
      expect(t.cardGap, TenturaSpacing.cardGap);
      expect(t.screenHPadding, TenturaSpacing.screenH);
      expect(t.rowGap, TenturaSpacing.row);
      expect(t.sectionGap, TenturaSpacing.section);
      expect(t.iconTextGap, TenturaSpacing.iconText);
      expect(t.avatarTextGap, TenturaSpacing.avatarText);
      expect(t.contentMaxWidth, isNull);
    });

    test('regular bumps spacing and caps content width', () {
      final t = TenturaTokens.light.applyWindowClass(WindowClass.regular);
      expect(t.cardPadding, const EdgeInsets.all(14));
      expect(t.cardGap, 11);
      expect(t.screenHPadding, 20);
      expect(t.contentMaxWidth, 560);
    });

    test('expanded uses widest spacing tier', () {
      final t = TenturaTokens.light.applyWindowClass(WindowClass.expanded);
      expect(t.cardPadding, const EdgeInsets.all(16));
      expect(t.cardGap, 12);
      expect(t.screenHPadding, 24);
      expect(t.contentMaxWidth, 720);
    });
  });
}
