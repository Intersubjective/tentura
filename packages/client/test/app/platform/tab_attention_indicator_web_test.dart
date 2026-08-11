@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/app/platform/tab_attention_indicator.dart';
import 'package:tentura/design_system/tentura_tab_indicator.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';

JSObject get _window => web.window as JSObject;

const _testFaviconDataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAD0lEQVQImWNgYGAEgAAAABUAABB0xgAAAABJRU5ErkJggg==';

void main() {
  group('TabAttentionIndicator (web)', () {
    late TabAttentionIndicator indicator;
    late TenturaTabIndicatorStyle style;
    const baseTitle = 'Tentura';

    setUp(() {
      web.document.title = baseTitle;
      _removeManagedFaviconLink();
      _ensureTestFavicon();
      indicator = TabAttentionIndicator();
      style = TenturaTabIndicator.resolve(Brightness.light);
    });

    tearDown(() {
      indicator.dispose();
      _removeManagedFaviconLink();
      _removeAllIconLinks();
      web.document.title = baseTitle;
      _window.delete('__tenturaForceTabBackground'.toJS);
    });

    test('apply writes document.title directly without a Flutter pump', () {
      indicator.apply(
        (count: 2, label: '2'),
        style,
        baseTitle: baseTitle,
      );

      expect(web.document.title, '(2) Tentura');
    });

    test('clear apply restores base title directly', () {
      indicator.apply(
        (count: 1, label: '1'),
        style,
        baseTitle: baseTitle,
      );
      indicator.apply(
        tabAttentionNone,
        style,
        baseTitle: baseTitle,
      );

      expect(web.document.title, baseTitle);
    });

    test('init leaves exactly one managed icon link', () {
      final links = web.document.querySelectorAll('link[rel~="icon"]');
      expect(links.length, 1);
      expect(
        web.document.getElementById('tentura-tab-attention-favicon'),
        isNotNull,
      );
    });

    test('hot-restart reuses the managed icon link', () {
      final firstLink = web.document.getElementById(
        'tentura-tab-attention-favicon',
      );
      indicator.dispose();

      final restarted = TabAttentionIndicator();
      addTearDown(restarted.dispose);

      final links = web.document.querySelectorAll('link[rel~="icon"]');
      expect(links.length, 1);
      expect(
        web.document.getElementById('tentura-tab-attention-favicon'),
        same(firstLink),
      );
    });

    test('active favicon uses data URL then clear restores pristine href', () async {
      final link = web.document.getElementById(
        'tentura-tab-attention-favicon',
      ) as web.HTMLLinkElement;
      final pristine = link.dataset['staticHref'] ?? 'favicon.png';

      indicator.apply(
        (count: 1, label: '1'),
        style,
        baseTitle: baseTitle,
      );

      await _waitForPaintedFavicon(link, pristine);

      final paintedHref = link.href;
      expect(paintedHref.startsWith('data:image/png'), isTrue);
      expect(paintedHref, isNot(equals(pristine)));

      indicator.apply(
        tabAttentionNone,
        style,
        baseTitle: baseTitle,
      );

      expect(link.getAttribute('href'), equals(pristine));
      expect(link.href, isNot(equals(paintedHref)));
    });

    test('badging is skipped in a normal browser tab', () {
      indicator.apply(
        (count: 4, label: '4'),
        style,
        baseTitle: baseTitle,
      );

      final qa = _readQaState();
      expect(qa, isNotNull, reason: 'run with --dart-define=QA_INTEGRATION_TEST_MODE=true');
      expect(qa!['badgeApplied'], isFalse);
    });

    test('missing setAppBadge does not break title apply', () {
      final navigator = web.window.navigator as JSObject;
      final hadBadge = navigator.has('setAppBadge');
      if (hadBadge) {
        navigator.delete('setAppBadge'.toJS);
      }

      expect(
        () => indicator.apply(
          (count: 7, label: '7'),
          style,
          baseTitle: baseTitle,
        ),
        returnsNormally,
      );
      expect(web.document.title, '(7) Tentura');
    });
  });
}

void _removeManagedFaviconLink() {
  web.document.getElementById('tentura-tab-attention-favicon')?.remove();
}

void _removeAllIconLinks() {
  final iconLinks = web.document.querySelectorAll('link[rel~="icon"]');
  for (var i = iconLinks.length - 1; i >= 0; i--) {
    final node = iconLinks.item(i);
    if (node case final web.Element element) {
      element.remove();
    }
  }
}

void _ensureTestFavicon() {
  _removeAllIconLinks();
  final link = web.document.createElement('link') as web.HTMLLinkElement
    ..rel = 'icon'
    ..href = _testFaviconDataUrl;
  web.document.head?.appendChild(link);
}

Future<void> _waitForPaintedFavicon(
  web.HTMLLinkElement link,
  String pristine,
) async {
  for (var i = 0; i < 50; i++) {
    final href = link.href;
    if (href.startsWith('data:image/png') && href != pristine) return;
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Map<String, Object?>? _readQaState() {
  final raw = _window.getProperty('__tenturaTabAttention'.toJS);
  if (raw == null || !raw.isA<JSObject>()) return null;
  final dartified = (raw as JSObject).dartify();
  if (dartified is! Map) return null;
  return Map<String, Object?>.from(dartified);
}
