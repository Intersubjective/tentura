// Tapping a file attachment in a Chat downloads it, hands the bytes to the
// platform file-open seam (share_plus platform) and shows the open-failed
// snackbar only on a genuine failure; the real cause is logged.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
// Transitive dependency: the platform seam under share_plus.
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_file_attachment_open.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_file_open_support.dart';

void main() {
  late FakeDownloadRepository repo;
  late LogCapture logs;
  late RecordingShare share;

  setUpAll(() => share = installRecordingShare());

  setUp(() async {
    repo = FakeDownloadRepository();
    share.reset();
    logs = LogCapture();
    await registerOpenDeps(caseOver(repo));
  });

  tearDown(() async {
    await logs.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpButton(
    WidgetTester tester,
    RoomMessageAttachment attachment, {
    Locale locale = const Locale('en'),
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openRoomFileAttachment(
              context,
              L10n.of(context)!,
              attachment,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Future<void> pumpAndTap(
    WidgetTester tester,
    RoomMessageAttachment attachment, {
    Locale locale = const Locale('en'),
  }) async {
    await pumpButton(tester, attachment, locale: locale);
    await tester.tap(find.text('open'));
    await pumpPastWork(tester);
  }

  testWidgets('a downloaded file reaches the share seam once with its bytes, '
      'name and mime, and no snackbar appears', (tester) async {
    await pumpAndTap(tester, fileAttachment());

    expect(repo.downloaded, ['A1']);
    final opened = await share.openedFiles();
    expect(opened, hasLength(1));
    expect(opened.single.bytes, [1, 2, 3]);
    expect(opened.single.name, 'report.pdf');
    expect(opened.single.mime, 'application/pdf');
    expect(openFailedSnackBar(), findsNothing);
  });

  testWidgets('blank file name is handed over as "file" and padded names are '
      'trimmed', (tester) async {
    await pumpAndTap(tester, fileAttachment(fileName: '   '));
    expect((await share.openedFiles()).single.name, 'file');

    share.shared.clear();
    await pumpAndTap(tester, fileAttachment(fileName: ' a.txt '));
    expect((await share.openedFiles()).single.name, 'a.txt');
  });

  testWidgets('a failing download shows the snackbar once, never reaches the '
      'seam and logs the real cause with its stack trace', (tester) async {
    final cause = StateError('http 404 for A1');
    repo.onDownload = (_) async => throw cause;

    await pumpAndTap(tester, fileAttachment());

    expect(share.shared, isEmpty);
    expect(openFailedSnackBar(), findsOneWidget);
    expect(logs.loggedErrorWithStack(cause), isTrue);
  });

  testWidgets('a failing open step shows the snackbar once and logs the '
      "seam's exception with its stack trace", (tester) async {
    final cause = StateError('share unavailable');
    share.error = cause;

    await pumpAndTap(tester, fileAttachment());

    expect(openFailedSnackBar(), findsOneWidget);
    expect(logs.loggedErrorWithStack(cause), isTrue);
  });

  testWidgets('the failure snackbar is localised in Russian', (tester) async {
    final cause = StateError('http 500');
    repo.onDownload = (_) async => throw cause;

    await pumpAndTap(tester, fileAttachment(), locale: const Locale('ru'));

    expect(openFailedSnackBar(text: kOpenFailedRu), findsOneWidget);
    expect(logs.loggedError(cause), isTrue);
  });

  // share_plus-specific: the cancel result of the native share sheet.
  testWidgets('dismissing the share sheet is not a failure: no snackbar and '
      'no error log', (tester) async {
    share.status = ShareResultStatus.dismissed;

    await pumpAndTap(tester, fileAttachment());

    expect(share.shared, hasLength(1));
    expect(openFailedSnackBar(), findsNothing);
    expect(logs.records.where((r) => r.level >= Level.WARNING), isEmpty);
  });

  group('widget disposed before the download completes', () {
    Future<Completer<Uint8List>> tapThenDispose(WidgetTester tester) async {
      final gate = Completer<Uint8List>();
      repo.onDownload = (_) => gate.future;
      await pumpButton(tester, fileAttachment());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      return gate;
    }

    testWidgets('a failed download shows no snackbar, throws nothing and is '
        'still logged', (tester) async {
      final cause = StateError('late failure');
      final gate = await tapThenDispose(tester);
      gate.completeError(cause);
      await pumpPastWork(tester);

      expect(tester.takeException(), isNull);
      expect(openFailedSnackBar(), findsNothing);
      expect(logs.loggedErrorWithStack(cause), isTrue);
    });

    testWidgets('a successful download shows no snackbar and throws '
        'nothing', (tester) async {
      final gate = await tapThenDispose(tester);
      gate.complete(Uint8List.fromList([1, 2, 3]));
      await pumpPastWork(tester);

      expect(tester.takeException(), isNull);
      expect(openFailedSnackBar(), findsNothing);
    });

    testWidgets('a seam failure after dispose shows no snackbar and throws '
        'nothing', (tester) async {
      final cause = StateError('share unavailable late');
      share.error = cause;
      final gate = await tapThenDispose(tester);
      gate.complete(Uint8List.fromList([1, 2, 3]));
      await pumpPastWork(tester);

      expect(tester.takeException(), isNull);
      expect(openFailedSnackBar(), findsNothing);
    });
  });
}
