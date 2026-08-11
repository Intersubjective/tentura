import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/platform/tab_attention_indicator.dart';
import 'package:tentura/design_system/tentura_tab_indicator.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';

void main() {
  group('TabAttentionIndicator (VM stub)', () {
    late TabAttentionIndicator indicator;
    late TenturaTabIndicatorStyle style;

    setUp(() {
      indicator = TabAttentionIndicator();
      style = TenturaTabIndicator.resolve(Brightness.light);
    });

    tearDown(() {
      indicator.dispose();
    });

    test('conditional export resolves to native no-op implementation', () {
      expect(indicator.isBackground, isFalse);
    });

    test('backgroundChanges is empty and emits nothing', () async {
      final events = <bool>[];
      final subscription = indicator.backgroundChanges.listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events, isEmpty);
      await subscription.cancel();
    });

    test('apply with active display is a safe no-op', () {
      expect(
        () => indicator.apply(
          (count: 3, label: '3'),
          style,
          baseTitle: 'Tentura',
        ),
        returnsNormally,
      );
    });

    test('apply with clear display is a safe no-op', () {
      expect(
        () => indicator.apply(
          tabAttentionNone,
          style,
          baseTitle: 'Tentura',
        ),
        returnsNormally,
      );
    });

    test('dispose is idempotent and safe', () {
      indicator.dispose();
      expect(indicator.dispose, returnsNormally);
    });
  });
}
