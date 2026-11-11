// Shared HTTP fake for the server-backed Post draft composer wire tests: it
// answers each GraphQL operation the Post composer, picker and forward flow
// send, so the production Ferry client, mappers and repositories stay in path.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_wire_harness.dart' show WireSent;

const postDraftWireDraftId = 'Bpostdraft001';
const postDraftWireAttachmentId = 'Adraftphoto01';
const postDraftWireRecipients = ['Urecipient001', 'Urecipient002'];

List<Map<String, dynamic>> restoredPostAttachments() => [
  for (var i = 0; i < 2; i++)
    {
      '__typename': 'post_draft_attachment',
      'id': 'Asavedfile00$i',
      'beacon_id': postDraftWireDraftId,
      'kind': 2,
      'position': i,
      'file_name': 'saved-${i + 1}.txt',
      'file_url': 'https://draft.test/attachments/saved-${i + 1}.txt',
      'mime': 'text/plain',
      'size_bytes': 5,
      'image_id': null,
      'image': null,
      'width': null,
      'height': null,
    },
];

Map<String, dynamic> _beacon({
  String body = 'hello',
  int policy = 1,
  int lifetimeHours = 72,
  List<Map<String, dynamic>> draftAttachments = const [],
}) => {
  '__typename': 'beacon',
  'id': postDraftWireDraftId,
  'title': '',
  'description': body,
  'kind': 1,
  'forward_policy': policy,
  'post_lifetime_hours': lifetimeHours,
  // The server-owned draft relation must be fetched and mapped by C1.
  // The old generated mapper ignores these fields, exposing the missing UI.
  'post_draft_attachments': draftAttachments,
  'cover_source': 0,
  'needs': '',
  'tags': '',
  'status': 3,
  'created_at': '2026-11-09T12:00:00Z',
  'updated_at': '2026-11-09T12:00:00Z',
  'is_discoverable': false,
  'beacon_images': <Object>[],
  'active_help_offers': <Object>[],
  'participant_help_offers': <Object>[],
  'admitted_helpers': <Object>[],
  'author': {
    '__typename': 'user',
    'id': 'Uviewer000001',
    'display_name': 'Олег',
    'description': '',
    'scores': <Object>[],
  },
  'help_offers_aggregate': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'unanswered_help_offers': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'admitted_helpers_aggregate': {
    '__typename': 'beacon_admitted_helper_aggregate',
    'aggregate': null,
  },
};

class PostDraftWire {
  final sent = <WireSent>[];
  final clock = Stopwatch()..start();
  final receivedAt = <WireSent, Duration>{};
  final multipartBodies = <String>[];
  String body = 'hello';
  int policy = 1;
  int lifetimeHours = 72;
  List<Map<String, dynamic>> draftAttachments = [];
  final addedIds = <String>[];

  List<WireSent> calls(String name) =>
      sent.where((r) => r.operationName == name).toList();

  Future<http.Response> respond(http.Request request) async {
    if (request.method == 'GET' &&
        request.url.path.startsWith('/attachments/')) {
      return http.Response(
        'saved',
        200,
        headers: {'content-type': 'text/plain'},
      );
    }
    Map<String, dynamic> data;
    if (request.url.path.endsWith('/session/access-token')) {
      data = {
        'subject': 'Uviewer000001',
        'access_token': 'test-token',
        'expires_in': 3600,
      };
    } else {
      final raw = utf8.decode(request.bodyBytes, allowMalformed: true);
      final multipart =
          request.headers['content-type']?.startsWith('multipart/') ?? false;
      final String operations;
      if (multipart) {
        multipartBodies.add(raw);
        operations = RegExp(
          r'name="operations"\r\n\r\n(.*?)\r\n--',
          dotAll: true,
        ).firstMatch(raw)!.group(1)!;
      } else {
        operations = raw;
      }
      final payload = jsonDecode(operations) as Map<String, dynamic>;
      final call = (
        operationName: payload['operationName'] as String,
        variables: (payload['variables'] as Map).cast<String, dynamic>(),
      );
      sent.add(call);
      receivedAt[call] = clock.elapsed;
      if (call.operationName == 'PostUpdateDraft') {
        body = call.variables['body'] as String;
        policy = call.variables['forwardPolicy'] as int;
        lifetimeHours =
            call.variables['lifetimeHours'] as int? ?? lifetimeHours;
      }
      final fields = switch (call.operationName) {
        'BeaconFetchById' => {
          'beacon_by_pk': _beacon(
            body: body,
            policy: policy,
            lifetimeHours: lifetimeHours,
            draftAttachments: draftAttachments,
          ),
        },
        'BeaconCreate' => {
          'beaconCreate': {
            '__typename': 'v2_Beacon',
            'id': postDraftWireDraftId,
          },
        },
        'BeaconUpdateDraft' => {
          'beaconUpdateDraft': {
            '__typename': 'v2_Beacon',
            'id': postDraftWireDraftId,
          },
        },
        'BeaconPublish' => {
          'beaconPublish': {
            '__typename': 'v2_Beacon',
            'id': postDraftWireDraftId,
          },
        },
        'PostUpdateDraft' => {
          'postUpdateDraft': {
            '__typename': 'v2_Beacon',
            'id': postDraftWireDraftId,
          },
        },
        'PostDraftAttachmentAdd' => {
          'postDraftAttachmentAdd': postDraftWireAttachmentId,
        },
        'PostDraftAttachmentRemove' => {'postDraftAttachmentRemove': true},
        'PostPublish' => {
          'postPublish': {
            '__typename': 'v2_PostPublishResult',
            'beaconId': postDraftWireDraftId,
            'rootMessageId': 'Mroot00000001',
          },
        },
        'ForwardCandidatesFetch' => {
          'forwardCandidates': [
            for (final id in postDraftWireRecipients)
              {
                '__typename': 'v2_user',
                'id': id,
                'displayName': id == postDraftWireRecipients.first
                    ? 'Мария'
                    : 'Анна',
                'description': '',
                'my_vote': 1,
                'trusts_viewer': true,
                'is_mutual_friend': true,
                'shares_active_context': false,
                'scores': <Object>[],
              },
          ],
        },
        'ForwardBeacon' => {
          'beaconForward': {
            '__typename': 'v2_ForwardDeliveryResult',
            'batchId': 'batch-1',
            'deliveredRecipientIds': postDraftWireRecipients,
            'availabilitySkippedRecipientIds': <Object>[],
            'alreadyForwardedRecipientIds': <Object>[],
            'blockedSkippedRecipientIds': <Object>[],
          },
        },
        _ => throw StateError(
          'Unexpected transport operation: ${call.operationName}',
        ),
      };
      if (call.operationName == 'PostDraftAttachmentAdd') {
        addedIds.add(postDraftWireAttachmentId);
      }
      data = {'data': fields};
    }
    return http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
