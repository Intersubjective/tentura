import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' show parseString;
import 'package:gql_exec/gql_exec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

import 'package:tentura/data/gql/tentura_v2_upload.dart';
import 'package:tentura/data/service/remote_api_client/v2_upload_multipart_link.dart';

void main() {
  Request reqWith(Map<String, dynamic> vars, String op, String doc) => Request(
    operation: Operation(document: parseString(doc), operationName: op),
    variables: vars,
  );

  final uri = Uri.parse('https://example.test/api/v2/graphql');

  test('encodes filename/type in operations and bytes in part 0', () async {
    late http.BaseRequest captured;
    final client = MockClient.streaming((req, bodyStream) async {
      captured = req;
      // Drain the body so finalize completes cleanly.
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(
          utf8.encode('{"data":{"RoomMessageAttachmentAdd":true}}'),
        ),
        200,
      );
    });

    final link = V2UploadMultipartLink(
      uri: uri,
      httpClient: client,
      defaultHeaders: const {},
    );

    final upload = TenturaV2Upload(
      filename: 'report.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    await link
        .request(
          reqWith(
            {'beaconId': 'b', 'messageId': 'm', 'file': upload},
            'RoomMessageAttachmentAdd',
            r'mutation RoomMessageAttachmentAdd($beaconId: String!, '
                r'$messageId: String!, $file: v2_Upload!) '
                r'{ RoomMessageAttachmentAdd(beaconId: $beaconId, '
                r'messageId: $messageId, file: $file) }',
          ),
        )
        .first;

    final multipart = captured as http.MultipartRequest;
    final ops = jsonDecode(multipart.fields['operations']!) as Map;
    expect((ops['variables'] as Map)['file'], {
      'filename': 'report.pdf',
      'type': 'application/pdf',
    });
    expect(jsonDecode(multipart.fields['map']!), {
      '0': ['variables.file'],
    });
    expect(multipart.files.single.field, '0');
    expect(multipart.files.single.filename, 'report.pdf');
  });

  test('forwards requests without an upload', () async {
    final client = MockClient((_) async => fail('should not POST'));
    final link = V2UploadMultipartLink(
      uri: uri,
      httpClient: client,
      defaultHeaders: const {},
    );

    var forwarded = false;
    await link
        .request(
          reqWith(
            {'beaconId': 'b'},
            'BeaconClose',
            r'mutation BeaconClose($beaconId: String!) '
                r'{ BeaconClose(beaconId: $beaconId) }',
          ),
          (r) {
            forwarded = true;
            return Stream.value(
              const Response(data: {}, response: {}),
            );
          },
        )
        .first;

    expect(forwarded, isTrue);
  });
}
