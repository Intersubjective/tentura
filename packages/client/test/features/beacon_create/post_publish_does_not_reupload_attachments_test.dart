// Publishing a Post sends the text only. The photos and files in the
// composer are saved on the server draft as they are picked (the composer's
// draft-upload step), so publication carries no upload and attaches nothing
// to the root message afterwards: the server moves the saved draft rows.
// The move itself is proven against Postgres in the server suite
// (post_draft_attachment_pg_test.dart).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/post_publish_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

void main() {
  test(
    'publishing a Post does not upload attachments with the publish call '
    'or afterwards',
    () async {
      final sent = <_Sent>[];
      final published = await http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          final effects = FakeUiEffectPort();
          final cubit = BeaconCreateCubit(
            kind: BeaconKind.post,
            beaconCreateCase: fakeBeaconCreateCase(),
            postPublishCase: PostPublishCase(PostPublishRepository(remote)),
            effects: effects,
          );
          final forward = ForwardCubit(
            beaconId: 'server-beacon',
            embedded: true,
            effects: effects,
            debugSkipInitialLoad: true,
            debugInitialState: const ForwardState(beaconId: 'server-beacon'),
          );
          try {
            await remote.setSessionAuth();
            final draftId = await cubit.ensureDraft(
              context: '',
              showMessage: false,
            );
            expect(draftId, 'server-beacon');
            return await cubit.publishPost(
              body: 'A note with files already saved',
              mentions: const [],
              forwardCubit: forward,
              forwardPolicy: BeaconForwardPolicyValue.open,
              attachments: [
                RoomPendingUpload(
                  bytes: Uint8List.fromList(const [0xD1, 0xA4, 0x71, 0x01]),
                  fileName: 'saved-photo.png',
                  mimeType: 'image/png',
                ),
                RoomPendingUpload(
                  bytes: Uint8List.fromList(const [0xD1, 0xA4, 0x71, 0x02]),
                  fileName: 'saved-notes.txt',
                  mimeType: 'text/plain',
                ),
              ],
            );
          } finally {
            await cubit.close();
            await forward.close();
            await remote.close();
          }
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return http.Response(
              jsonEncode({
                'subject': 'Uauthor000001',
                'access_token': 'test-token',
                'expires_in': 3600,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          sent.add(_Sent.from(request));
          final operation = sent.last.operation;
          final data = operation == 'RoomMessageAttachmentAdd'
              ? {
                  '__typename': 'mutation_root',
                  'RoomMessageAttachmentAdd': true,
                }
              : {
                  '__typename': 'mutation_root',
                  'postPublish': {
                    '__typename': 'v2_PostPublishResult',
                    'beaconId': 'server-beacon',
                    'rootMessageId': 'Mroot00000001',
                    'expiresAt': null,
                  },
                };
          return http.Response(
            jsonEncode({'data': data}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(published, isTrue);
      expect(
        sent.map((request) => request.operation).toList(),
        ['PostPublish'],
        reason: 'attachments already stored on the draft are not sent again',
      );
      expect(sent.single.uploadsAFile, isFalse);
    },
  );
}

final class _Sent {
  _Sent({required this.operation, required this.uploadsAFile});

  factory _Sent.from(http.Request request) {
    final body = request.body;
    final type = request.headers['content-type'] ?? '';
    final multipart = type.contains('multipart');
    return _Sent(
      operation: _operationName(body),
      uploadsAFile:
          multipart ||
          body.contains('saved-photo.png') ||
          body.contains('saved-notes.txt'),
    );
  }

  final String operation;
  final bool uploadsAFile;
}

String _operationName(String body) {
  final match = RegExp(
    r'"operationName"\s*:\s*"([^"]+)"',
  ).firstMatch(body);
  return match?.group(1) ?? '';
}
