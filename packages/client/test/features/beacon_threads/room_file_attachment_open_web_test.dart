@TestOn('browser')
library;

// On the web a file attachment is saved through a browser download under the
// attachment's file name and mime type (no share sheet), with the downloaded
// bytes; a failed download shows the snackbar and no browser download.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import 'package:tentura/features/beacon_threads/ui/widget/room_file_attachment_open.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_file_open_support.dart';

/// Observes browser downloads without starting real ones and without
/// assuming how the app triggers them: any click on an anchor that has a
/// `download` attribute (direct `click()` or a dispatched click event) is
/// recorded with the name, the mime type and the bytes behind its URL. Share
/// sheet calls (`navigator.share`) are counted when the browser has one.
const _observer = '''
(function () {
  window.__downloads = [];
  window.__shareCalls = 0;
  window.__failDownload = false;
  function record(anchor) {
    if (!anchor.hasAttribute('download')) return false;
    if (window.__failDownload) throw new Error('download blocked');
    var entry = { name: anchor.download, type: null, bytes: null };
    entry.done = fetch(anchor.href)
      .then(function (r) {
        entry.type = r.headers.get('content-type');
        return r.arrayBuffer();
      })
      .then(function (b) { entry.bytes = Array.from(new Uint8Array(b)); });
    window.__downloads.push(entry);
    return true;
  }
  HTMLAnchorElement.prototype.click = function () { record(this); };
  var dispatch = EventTarget.prototype.dispatchEvent;
  EventTarget.prototype.dispatchEvent = function (event) {
    if (this instanceof HTMLAnchorElement && event.type === 'click' &&
        record(this)) {
      return true;
    }
    return dispatch.call(this, event);
  };
  if (navigator.share) {
    navigator.share = function () {
      window.__shareCalls++;
      return Promise.resolve();
    };
  }
})();
''';

int _downloadCount() =>
    (globalContext['__downloads']! as JSArray<JSObject>).length;

/// Waits (bounded) for the app to start a browser download.
Future<void> _waitForDownload(WidgetTester tester) async {
  for (var i = 0; i < 50 && _downloadCount() == 0; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

void main() {
  late LogCapture logs;

  setUp(() {
    globalContext.callMethod<JSAny?>('eval'.toJS, _observer.toJS);
    logs = LogCapture();
  });
  tearDown(() async {
    await logs.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpAndTap(WidgetTester tester, RealDownload download) async {
    await download.register();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openRoomFileAttachment(
                context,
                L10n.of(context)!,
                fileAttachment(fileName: ' report.pdf '),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  testWidgets('tapping a file attachment starts one browser download with '
      "the attachment's name, mime type and bytes, no share sheet and no "
      'snackbar', (tester) async {
    await withRealDownloadPath((download) async {
      await pumpAndTap(tester, download);
      await _waitForDownload(tester);

      expect(_downloadCount(), 1, reason: 'one browser download expected');
      final entry = (globalContext['__downloads']! as JSArray<JSObject>)[0];
      expect((entry['name']! as JSString).toDart, 'report.pdf');
      await tester.runAsync(
        () => (entry['done']! as JSPromise<JSAny?>).toDart,
      );
      expect(
        (entry['type']! as JSString).toDart,
        startsWith('application/pdf'),
      );
      final bytes = (entry['bytes']! as JSArray<JSNumber>).toDart
          .map((n) => n.toDartInt)
          .toList();
      expect(bytes, [4, 5, 6]);
      expect((globalContext['__shareCalls']! as JSNumber).toDartInt, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(openFailedSnackBar(), findsNothing);
    });
  });

  testWidgets('a failed download shows the snackbar, starts no browser '
      'download and logs the cause', (tester) async {
    await withRealDownloadPath(
      attachmentResponse: (_) => http.Response('nope', 500),
      (download) async {
        await pumpAndTap(tester, download);
        for (var i = 0; i < 50; i++) {
          if (openFailedSnackBar().evaluate().isNotEmpty) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(openFailedSnackBar(), findsOneWidget);
        expect(_downloadCount(), 0);
        expect(
          logs.records.any((r) => r.error != null && r.stackTrace != null),
          isTrue,
        );
      },
    );
  });

  testWidgets('when the browser refuses the download the snackbar shows '
      'once and the cause is logged', (tester) async {
    globalContext['__failDownload'] = true.toJS;
    await withRealDownloadPath((download) async {
      await pumpAndTap(tester, download);
      for (var i = 0; i < 50; i++) {
        if (openFailedSnackBar().evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(openFailedSnackBar(), findsOneWidget);
      expect(_downloadCount(), 0);
      expect(
        logs.records.any((r) => r.error != null && r.stackTrace != null),
        isTrue,
      );
    });
  });
}
