import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #410: the web engine's Noto fallback fonts (emoji included) come from
/// fonts.gstatic.com; index.html opens that connection before the engine
/// asks for them so first paint does not wait on DNS/TLS.
void main() {
  test('index.html preconnects to the fallback font host with CORS', () {
    final index = File('web/index.html').readAsStringSync();
    final preconnect = RegExp(
      r'<link[^>]*rel="preconnect"[^>]*href="https://fonts\.gstatic\.com"[^>]*>',
    ).firstMatch(index);
    expect(preconnect, isNotNull, reason: 'missing preconnect');
    expect(preconnect!.group(0), contains('crossorigin'));
  });
}
