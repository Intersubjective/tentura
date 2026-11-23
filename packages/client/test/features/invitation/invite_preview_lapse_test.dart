import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';

import '../../data/service/_session_account_test_harness.dart';

void main() {
  for (final (description, wireFlag, expected) in [
    ('parses a lapsed Request with its title', {'lapsed': true}, true),
    (
      'defaults to false for a preview without lapse information',
      <String, bool>{},
      false,
    ),
  ]) {
    test(description, () {
      final preview = InvitePreview.fromJson({
        'beacon': {'kind': 'request', 'title': 'T', ...wireFlag},
      });

      expect(
        preview.beacon,
        isA<InvitePreviewBeacon>()
            .having((beacon) => beacon.title, 'title', 'T')
            .having((beacon) => beacon.lapsed, 'lapsed', expected),
      );
    });
  }

  test(
    'fetches a lapsed Request preview with the issuer and Request title',
    () async {
      final preview = await http.runWithClient(
        () async {
          final remote = testRealtimeClient();
          final repository = InvitationRepository(remote);
          addTearDown(remote.close);
          addTearDown(repository.dispose);
          await remote.setSessionAuth();
          return repository.fetchInvitePreview('garden-code');
        },
        () => MockClient((request) async {
          final Map<String, Object?> body;
          if (request.url.path == '/api/v2/session/access-token') {
            expect(request.method, 'POST');
            body = {
              'subject': 'Uviewer000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            };
          } else {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/v2/invite/garden-code/preview');
            expect(request.headers['Authorization'], 'Bearer test-token');
            body = {
              'codeStatus': 'available',
              'callerStatus': 'existing-user',
              'suggestedAction': 'accept-as-existing',
              'inviter': {'id': 'Uissuer000001', 'displayName': 'Mira'},
              'beacon': {
                'id': 'Bgarden000001',
                'kind': 'request',
                'title': 'Community garden',
                'lapsed': true,
              },
            };
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(preview.isAvailable, isTrue);
      expect(preview.inviter?.displayName, 'Mira');
      expect(
        preview.beacon,
        isA<InvitePreviewBeacon>()
            .having((beacon) => beacon.title, 'title', 'Community garden')
            .having((beacon) => beacon.lapsed, 'lapsed', isTrue),
      );
    },
  );
}
