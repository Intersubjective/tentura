// Every place that lists a Chat file attachment (Chat body, Post root card,
// pinned fact card) opens it through the real download path: authenticated
// GET of the tapped attachment's id over the real repository, then the bytes
// reach the platform file-open seam under the attachment's name and mime,
// with no open-failed snackbar. Only the HTTP client is faked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/widget/post_root_pin_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_body_harness.dart';
import 'support/room_file_open_support.dart';

const _author = Profile(id: 'Uauthor', displayName: 'Author');

RoomMessage _messageWithFile(String id) => RoomMessage(
  id: id,
  beaconId: 'b1',
  authorId: _author.id,
  author: _author,
  body: 'See the attached file',
  createdAt: DateTime.utc(2026, 11, 1, 12),
  attachments: [fileAttachment(id: 'Aroom123')],
);

Widget _app(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(390, 720)),
    child: TenturaResponsiveScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  late RecordingShare share;
  late LogCapture logs;

  setUpAll(() => share = installRecordingShare());
  setUp(() {
    share.reset();
    logs = LogCapture();
  });
  tearDown(() async {
    await logs.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpPostRoot(WidgetTester tester) {
    final root = _messageWithFile('Mroot1');
    return tester.pumpWidget(
      _app(
        PostRootPinCard(
          pin: RoomPostRootPin(
            messageId: root.id,
            excerpt: root.body,
            startedBy: _author.displayName,
          ),
          collapsed: false,
          onTap: () {},
          now: DateTime.utc(2026, 11, 1, 13),
          rootMessage: root,
          author: _author,
        ),
      ),
    );
  }

  Future<void> pumpFactCard(WidgetTester tester) => tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => BeaconPinnedFactCard(
          l10n: L10n.of(context)!,
          fact: BeaconFactCard(
            id: 'F1',
            beaconId: 'b1',
            factText: 'Fact with a file',
            visibility: 0,
            pinnedBy: 'U1',
            createdAt: DateTime.utc(2026),
            status: 0,
            attachments: [fileAttachment(id: 'Afact123')],
          ),
        ),
      ),
    ),
  );

  Future<void> pumpChatBody(WidgetTester tester) => pumpBeaconRoomBody(
    tester,
    enableComposer: false,
    roomState: roomBodyState(messages: [_messageWithFile('m1')]),
  );

  // (name, pump, id of the attachment shown there). The harness for the Chat
  // body resets GetIt, so dependencies are registered after pumping.
  final entries = <(String, Future<void> Function(WidgetTester), String)>[
    ('Chat body', pumpChatBody, 'Aroom123'),
    ('Post root card', pumpPostRoot, 'Aroom123'),
    ('pinned fact card', pumpFactCard, 'Afact123'),
  ];

  for (final (name, pump, attachmentId) in entries) {
    testWidgets('$name: tapping a file attachment downloads that attachment '
        'and hands it to the seam', (tester) async {
      await withRealDownloadPath((download) async {
        await pump(tester);
        await download.register();
        await tester.tap(find.textContaining('report.pdf').first);
        await pumpPastWork(tester);

        expect(download.requests, hasLength(1));
        expect(download.requests.single.url.path, endsWith('/$attachmentId'));
        expect(
          download.requests.single.headers['Authorization'],
          'Bearer test-token',
        );
        final opened = await share.openedFiles();
        expect(opened, hasLength(1));
        expect(opened.single.bytes, [4, 5, 6]);
        expect(opened.single.name, 'report.pdf');
        expect(opened.single.mime, 'application/pdf');
        expect(openFailedSnackBar(), findsNothing);
        expect(logs.records.where((r) => r.level >= Level.WARNING), isEmpty);
      });
    });

    testWidgets('$name: a server error on the attachment shows the snackbar '
        'once, never reaches the seam, and logs the server failure with its '
        'stack trace', (tester) async {
      await withRealDownloadPath(
        attachmentResponse: (_) => http.Response('nope', 404),
        (download) async {
          await pump(tester);
          await download.register();
          await tester.tap(find.textContaining('report.pdf').first);
          await pumpPastWork(tester);

          expect(share.shared, isEmpty);
          expect(openFailedSnackBar(), findsOneWidget);
          expect(
            logs.records.any(
              (r) => isServerFailure(r.error) && r.stackTrace != null,
            ),
            isTrue,
          );
        },
      );
    });
  }
}
