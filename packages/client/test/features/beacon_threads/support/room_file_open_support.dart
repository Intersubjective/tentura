// Shared fixtures for the "open a Chat file attachment" tests: a recording
// platform share seam, one log capture, and the real
// BeaconThreadsRepository -> RemoteApiService -> http transport chain with
// only the HTTP client faked.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
// Transitive dependency: the platform seam under share_plus.
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../../support/test_realtime_sync.dart';

const kOpenFailedEn = 'Could not open attachment.';
const kOpenFailedRu = 'Не удалось открыть вложение.';

RoomMessageAttachment fileAttachment({
  String id = 'A1',
  String fileName = 'report.pdf',
  String mime = 'application/pdf',
}) => RoomMessageAttachment(
  id: id,
  kind: 2,
  position: 0,
  mime: mime,
  sizeBytes: 3,
  fileName: fileName,
);

/// The platform seam. `SharePlus.instance` captures `SharePlatform.instance`
/// once, so [installRecordingShare] runs in `setUpAll` and each test calls
/// [reset].
class RecordingShare extends SharePlatform {
  final shared = <ShareParams>[];
  Object? error;
  ShareResultStatus status = ShareResultStatus.success;

  /// What the user's platform was asked to open or save. The only place the
  /// tests know the native seam is share_plus: a different seam changes this
  /// getter, not the tests.
  Future<List<({List<int> bytes, String name, String? mime})>>
  openedFiles() async => [
    for (final p in shared)
      (
        bytes: List<int>.of(await p.files!.single.readAsBytes()),
        name: effectiveShareName(p),
        mime: p.files!.single.mimeType,
      ),
  ];

  void reset() {
    shared.clear();
    error = null;
    status = ShareResultStatus.success;
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    // The faked seam fails with a configured arbitrary error.
    // ignore: only_throw_errors
    if (error != null) throw error!;
    shared.add(params);
    return ShareResult('', status);
  }
}

RecordingShare installRecordingShare() {
  final share = RecordingShare();
  SharePlatform.instance = share;
  return share;
}

/// The file name the platform would use: the override, else the XFile name.
String effectiveShareName(ShareParams p) {
  final override = p.fileNameOverrides?.firstOrNull;
  return (override != null && override.isNotEmpty)
      ? override
      : p.files!.single.name;
}

/// Collects every log record (children propagate to the root logger).
class LogCapture {
  LogCapture() {
    Logger.root.level = Level.ALL;
    _sub = Logger.root.onRecord.listen(records.add);
  }

  final records = <LogRecord>[];
  late final StreamSubscription<LogRecord> _sub;

  Future<void> dispose() => _sub.cancel();

  bool loggedError(Object cause) => records.any((r) => r.error == cause);

  bool loggedErrorWithStack(Object cause) =>
      records.any((r) => r.error == cause && r.stackTrace != null);
}

class _FakeFactCards extends Fake implements BeaconFactCardRepository {}

class _FakeHints extends Fake implements BeaconRoomHintsRepository {}

class _FakePolling extends Fake implements PollingRepository {}

/// A fake repository that serves [onDownload]; everything else is unused.
class FakeDownloadRepository extends Fake implements BeaconThreadsRepository {
  Future<Uint8List> Function(String id) onDownload = (_) async =>
      Uint8List.fromList([1, 2, 3]);
  final downloaded = <String>[];

  @override
  Future<Uint8List> downloadRoomAttachmentBytes(String attachmentId) {
    downloaded.add(attachmentId);
    return onDownload(attachmentId);
  }
}

BeaconThreadsCase caseOver(BeaconThreadsRepository repo) => BeaconThreadsCase(
  repo,
  _FakeFactCards(),
  _FakePolling(),
  _FakeHints(),
  RoomReadWatermarkStore.testing(),
  buildTestRealtimeSync().case_,
  env: const Env(),
  logger: Logger('test'),
);

/// Registers the use case and app logger the way the app does
/// (`Logger.root`). Call after any harness that resets GetIt.
Future<void> registerOpenDeps(BeaconThreadsCase threadsCase) async {
  await GetIt.I.reset();
  GetIt.I
    ..registerSingleton<Logger>(Logger.root)
    ..registerSingleton<BeaconThreadsCase>(threadsCase);
}

/// What the faked server saw and what it answers.
class RealDownload {
  RealDownload(this.threadsCase);

  final BeaconThreadsCase threadsCase;
  final requests = <http.Request>[];

  Future<void> register() => registerOpenDeps(threadsCase);
}

/// Runs [body] with the real repository, session-authenticated
/// RemoteApiService and `http` transport; only the HTTP client is faked.
/// Attachment downloads answer [attachmentResponse] (default: bytes
/// [4, 5, 6]). Everything inside [body] (taps included) must run in this
/// callback so the zone-scoped client is used.
Future<void> withRealDownloadPath(
  Future<void> Function(RealDownload download) body, {
  http.Response Function(http.Request request)? attachmentResponse,
}) {
  late RealDownload download;
  return http.runWithClient(
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      try {
        // Cookie-session auth uses the browser's own fetch on Chrome and
        // bypasses http.runWithClient; seeded auth keeps the token and the
        // download on the same faked transport on Chrome and the VM.
        await remote.setAuth(
          seed: base64Encode(List<int>.filled(32, 0)),
          authTokenFetcher: (_, _) async => Credentials(
            userId: 'Ueditor000001',
            accessToken: 'test-token',
            expiresAt: DateTime.timestamp().add(const Duration(hours: 1)),
          ),
        );
        download = RealDownload(
          caseOver(
            BeaconThreadsRepository(remote, buildTestRealtimeSync().port),
          ),
        );
        await body(download);
      } finally {
        await remote.close();
      }
    },
    () => MockClient((request) async {
      if (request.url.path.endsWith('/session/access-token')) {
        return http.Response(
          jsonEncode({
            'subject': 'Ueditor000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      download.requests.add(request);
      return (attachmentResponse ?? (_) => http.Response.bytes([4, 5, 6], 200))(
        request,
      );
    }),
  );
}

/// Not pumpAndSettle: it would run the snackbar to its auto-dismiss and make
/// every "snackbar shown / not shown" assertion vacuous.
Future<void> pumpPastWork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The failure of the 404 attachment response, as the repository raises it.
bool isServerFailure(Object? error) => error is ServerUnknownException;

Finder openFailedSnackBar({String text = kOpenFailedEn}) =>
    find.text(text, findRichText: true);
