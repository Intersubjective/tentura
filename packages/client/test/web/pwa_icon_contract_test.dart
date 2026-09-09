import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PWA install, apple-touch-icon, and push notifications share one stable
/// cache-busted filename at the site root — not Flutter's default
/// `icons/Icon-192.png` (iOS caches that name, and versioned builds move
/// `/icons/` under `/app-assets/<version>/`).
void main() {
  final webDir = Directory('web');

  const paths = [
    '/tentura-icon-192.png',
    '/tentura-icon-512.png',
    '/tentura-icon-maskable-192.png',
    '/tentura-icon-maskable-512.png',
  ];

  test('root PWA icons exist and are referenced by absolute cache-busted paths', () {
    for (final path in paths) {
      expect(
        File('${webDir.path}$path').existsSync(),
        isTrue,
        reason: 'missing web$path',
      );
    }

    final index = File('${webDir.path}/index.html').readAsStringSync();
    expect(index, contains('href="/tentura-icon-192.png"'));
    expect(index, isNot(contains('icons/Icon-192.png')));

    final decoded =
        jsonDecode(File('${webDir.path}/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final srcs = (decoded['icons'] as List)
        .cast<Map<String, dynamic>>()
        .map((icon) => icon['src'] as String)
        .toList();
    expect(srcs, containsAll(paths));
    for (final src in srcs) {
      expect(src.startsWith('/tentura-icon-'), isTrue, reason: src);
    }
  });
}
