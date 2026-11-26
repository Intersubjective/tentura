import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/private_avatar_repository_port.dart';

import '../http/cookies.dart';
import '_base_controller.dart';

@Injectable(order: 4)
final class PrivateAvatarDownloadController extends BaseController {
  PrivateAvatarDownloadController(super.env, this._avatars);

  static const path = '/api/v2/private-avatars';
  final PrivateAvatarRepositoryPort _avatars;

  @override
  Future<Response> handler(Request request) async {
    final viewer = request.context[kContextJwtKey];
    if (viewer is! JwtEntity) return Response.unauthorized(null);
    final key = request.url.queryParameters['objectKey'];
    if (key == null || key.isEmpty || key.contains('\u0000')) {
      return Response.badRequest(body: 'missing or invalid object key');
    }
    try {
      final bytes = await _avatars.get(viewerId: viewer.sub, objectKey: key);
      return Response.ok(
        bytes,
        headers: {
          kHeaderContentType: kContentTypeJpeg,
          kHeaderCacheControl: kCacheControlNoStore,
        },
      );
    } on UnauthorizedException {
      return Response.forbidden(null);
    } on IdNotFoundException {
      return Response.notFound(null);
    }
  }
}
