import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';

import '_base_controller.dart';

@Injectable(order: 4)
final class RoomAttachmentDownloadController extends BaseController {
  RoomAttachmentDownloadController(
    super.env,
    this._case,
  );

  final BeaconRoomCase _case;

  @override
  Future<Response> handler(Request request) async {
    final attachmentId = request.params['attachmentId'] ?? '';
    if (attachmentId.isEmpty) {
      return Response.badRequest(body: 'missing attachment id');
    }
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    if (jwt == null) {
      return Response.unauthorized(null);
    }
    try {
      final r = await _case.downloadAttachment(
        userId: jwt.sub,
        attachmentId: attachmentId,
      );
      final safeName = _asciiFallback(r.fileName);
      return Response.ok(
        r.bytes,
        headers: {
          kHeaderContentType: r.mime,
          'Content-Disposition': 'attachment; filename="$safeName"',
        },
      );
    } on IdNotFoundException {
      return Response.notFound(null);
    } on UnauthorizedException {
      return Response.forbidden(null);
    } on IdWrongException {
      return Response.badRequest(body: 'wrong attachment type');
    }
  }

  static String _asciiFallback(String name) {
    if (name.isEmpty) {
      return 'file';
    }
    final cleaned = name.replaceAll(RegExp(r'[^\x20-\x7E]+'), '_');
    return cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned;
  }
}
