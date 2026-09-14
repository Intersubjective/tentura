import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

/// Forced-background adapter regression (QA seam only).
///
/// Asserts `window.__tenturaTabAttention` after a real unread receipt while
/// `__tenturaForceTabBackground` is set before app init. Does **not** read or
/// assert live `document.title` — raw DOM title while genuinely hidden remains
/// a direct-CDP concern.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'forced-background QA seam reflects unread receipt and clears on visible',
    (tester) async {
      _setForceTabBackground(true);
      expect(
        _readForceTabBackground(),
        isTrue,
        reason: 'QA force flag must be readable before app init',
      );

      await launchApp(app.main);
      await tester.pumpAndSettle();

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('tab-attn-bg'),
      );
      final title = uniqueRequestTitle('IT tab attention bg');

      await logout(tester);
      await createAndForwardRequest(
        tester,
        fixture: fixture,
        title: title,
      );

      await logout(tester);
      await offerHelpFromInbox(
        tester,
        fixture: fixture,
        requestTitle: title,
      );

      await logout(tester);
      await loginAs(tester, fixture.authorEmail);
      // kPathUpdates now redirects to kPathInboxHistory (UNIT 20); navigate
      // to the canonical path directly so goToPath's URL wait doesn't race
      // the redirect.
      await goToPath(tester, kPathInboxHistory);

      // Real receipt must land in AttentionCase before we assert the adapter.
      await pumpUntil(
        tester,
        () => GetIt.I<AttentionCase>().snapshot.summary.unreadTotal >= 1,
        timeout: const Duration(seconds: 30),
      );

      // Controller caches isBackground from construction / visibility events.
      // Re-assert the QA override and notify so it re-reads after the receipt.
      _setForceTabBackground(true);
      _reemitTabBackground();
      await tester.pump();

      await _waitForQaState(
        tester,
        'activate unread indicator',
        () {
          final state = _readTabAttentionQaState();
          if (state == null) return false;
          final count = _asInt(state['count']);
          final label = state['label']?.toString() ?? '';
          final composedTitle = state['title']?.toString() ?? '';
          return count >= 1 && label.isNotEmpty && composedTitle.isNotEmpty;
        },
        timeout: const Duration(seconds: 20),
      );

      final active = _readTabAttentionQaState();
      expect(active, isNotNull);
      expect(_asInt(active!['count']), greaterThanOrEqualTo(1));
      expect(active['label']?.toString(), isNotEmpty);
      expect(active['title']?.toString(), isNotEmpty);
      debugPrint(
        '[tab-attn-bg] active QA state count=${active['count']} '
        'label=${active['label']} title=${active['title']}',
      );

      // Clear via "visible" transition: drop the QA force override and notify
      // the adapter so it re-reads isBackground (WebDriver cannot hide the tab).
      _setForceTabBackground(false);
      _reemitTabBackground();
      await tester.pump();

      await _waitForQaState(
        tester,
        'clear indicator on visible',
        () {
          final state = _readTabAttentionQaState();
          if (state == null) return false;
          final count = _asInt(state['count']);
          final label = state['label']?.toString() ?? '';
          return count == 0 && label.isEmpty;
        },
        timeout: const Duration(seconds: 10),
      );

      final cleared = _readTabAttentionQaState();
      expect(cleared, isNotNull);
      expect(_asInt(cleared!['count']), 0);
      expect(cleared['label']?.toString(), isEmpty);
      expect(cleared['title']?.toString(), isNotEmpty);
    },
  );
}

Future<void> _waitForQaState(
  WidgetTester tester,
  String step,
  bool Function() condition, {
  required Duration timeout,
}) async {
  try {
    await pumpUntil(tester, condition, timeout: timeout);
  } on TimeoutException catch (error) {
    throw StateError(
      '$step: qa=${_readTabAttentionQaState()} '
      'visibility=${web.document.visibilityState} forced=${_readForceTabBackground()} '
      'unread=${GetIt.I<AttentionCase>().snapshot.summary.unreadTotal}; $error',
    );
  }
}

JSObject get _window => web.window as JSObject;

void _setForceTabBackground(bool forced) {
  _window.setProperty('__tenturaForceTabBackground'.toJS, forced.toJS);
}

void _reemitTabBackground() {
  final reemit = _window.getProperty('__tenturaReemitTabBackground'.toJS);
  if (reemit != null && reemit.isA<JSFunction>()) {
    (reemit as JSFunction).callAsFunction();
    return;
  }
  // Fallback for older builds that only listen for visibilitychange.
  web.document.dispatchEvent(web.Event('visibilitychange'));
}

bool _readForceTabBackground() {
  final value = _window.getProperty('__tenturaForceTabBackground'.toJS);
  if (value == null || !value.isA<JSBoolean>()) return false;
  return (value as JSBoolean).toDart;
}

Map<String, Object?>? _readTabAttentionQaState() {
  final raw = _window.getProperty('__tenturaTabAttention'.toJS);
  if (raw == null || !raw.isA<JSObject>()) return null;
  final dartified = (raw as JSObject).dartify();
  if (dartified is! Map) return null;
  return Map<String, Object?>.from(dartified);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
