import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/room_attachment_download_controller.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

typedef _Download = ({Uint8List bytes, String mime, String fileName});

/// Answers `downloadAttachment` with a fixed PDF, or throws [error].
final class _FakeBeaconRoomCase implements BeaconRoomCase {
  Exception? error;

  final calls = <({String userId, String attachmentId})>[];

  @override
  Future<_Download> downloadAttachment({
    required String userId,
    required String attachmentId,
  }) async {
    calls.add((userId: userId, attachmentId: attachmentId));
    if (error case final Exception e) throw e;
    return (
      bytes: Uint8List.fromList([1, 2, 3]),
      mime: 'application/pdf',
      fileName: 'report.pdf',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeBeaconRoomCase roomCase;
  late RoomAttachmentDownloadController controller;

  setUp(() {
    roomCase = _FakeBeaconRoomCase();
    controller = RoomAttachmentDownloadController(
      Env(environment: Environment.test),
      roomCase,
    );
  });

  Request request({String attachmentId = 'Aatt', String? userId = 'Uviewer'}) =>
      Request(
        'GET',
        Uri.parse('http://localhost/api/v2/room/attachment/$attachmentId'),
        context: {
          'shelf_router/params': {'attachmentId': attachmentId},
          if (userId != null) kContextJwtKey: JwtEntity(sub: userId),
        },
      );

  test('400 without an attachment id', () async {
    final r = await controller.handler(request(attachmentId: ''));
    expect(r.statusCode, 400);
    expect(roomCase.calls, isEmpty);
  });

  test('401 without a jwt; the case is never asked', () async {
    final r = await controller.handler(request(userId: null));
    expect(r.statusCode, 401);
    expect(roomCase.calls, isEmpty);
  });

  test('200 streams the bytes with type and attachment disposition', () async {
    final r = await controller.handler(request());

    expect(r.statusCode, 200);
    expect(await r.read().expand((c) => c).toList(), [1, 2, 3]);
    expect(r.headers['content-type'], 'application/pdf');
    expect(r.headers['content-disposition'], contains('attachment'));
    expect(r.headers['content-disposition'], contains('report.pdf'));
    expect(roomCase.calls.single, (userId: 'Uviewer', attachmentId: 'Aatt'));
  });

  for (final (error, status) in <(Exception, int)>[
    (const IdNotFoundException(id: 'Aatt'), 404),
    (const UnauthorizedException(), 403),
    (const IdWrongException(), 400),
  ]) {
    test('${error.runtimeType} -> $status', () async {
      roomCase.error = error;
      final r = await controller.handler(request());
      expect(r.statusCode, status);
    });
  }
}
