import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';

// Issue #468: Settings > "Help types I can provide" opened a page about
// private tags other people leave on you. The row and the page title must
// name what the page actually does.
//
// Run from packages/client: the ARB files are read by relative path.
Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  const oldEn = 'Help types I can provide';
  const oldRu = 'Какие типы помощи я могу оказать';

  test('English row and page title read Tags others can give me', () {
    final l10n = lookupL10n(const Locale('en'));
    expect(l10n.settingsRoutingMute, 'Tags others can give me');
    expect(l10n.routingMuteScreenTitle, 'Tags others can give me');
  });

  test('Russian row and page title talk about tags, not help I provide', () {
    final l10n = lookupL10n(const Locale('ru'));
    final values = [l10n.settingsRoutingMute, l10n.routingMuteScreenTitle];
    for (final value in values) {
      expect(value, isNot(oldRu));
      expect(value.trim(), isNotEmpty);
      expect(value.toLowerCase(), matches(RegExp('т[еэ]г')));
      expect(value.toLowerCase(), isNot(contains('помощ')));
    }
    // Row and page carry the same name.
    expect(l10n.settingsRoutingMute, l10n.routingMuteScreenTitle);
  });

  test('ARB files carry the new copy and no stale translator note', () {
    final en = _arb('l10n/app_en.arb');
    final ru = _arb('l10n/app_ru.arb');
    for (final key in ['settingsRoutingMute', 'routingMuteScreenTitle']) {
      expect(en[key], 'Tags others can give me');
      expect(ru[key], isNot(oldRu));
    }
    expect(en.values.whereType<String>(), isNot(contains(oldEn)));
    final meta = en['@routingMuteScreenTitle'] as Map<String, dynamic>;
    final description = (meta['description'] as String? ?? '').toLowerCase();
    expect(description, isNot(contains('i can help with this')));
    expect(description, isNot(contains('help types the user can provide')));
  });
}
