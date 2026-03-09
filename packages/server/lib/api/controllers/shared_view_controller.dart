import 'package:injectable/injectable.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/comment_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/api/view/shared_view/shared_view_document.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/opinion_case.dart';

import '_base_controller.dart';

@Injectable(order: 3)
final class SharedViewController extends BaseController {
  const SharedViewController(
    this._beaconRepository,
    this._commentRepository,
    this._userRepository,
    this._invitationCase,
    this._opinionCase,
    super.env,
  );

  final BeaconRepository _beaconRepository;

  final CommentRepository _commentRepository;

  final UserRepository _userRepository;

  final InvitationCase _invitationCase;

  final OpinionCase _opinionCase;

  @override
  Future<Response> handler(Request request) async {
    if (!env.renderSharedPreview &&
        (request.headers['User-Agent']?.contains('Mozilla') ?? false)) {
      return Response.found(
        Uri(
          scheme: request.requestedUri.scheme,
          host: request.requestedUri.host,
          port: request.requestedUri.port,
          path: '/',
          fragment:
              '${request.requestedUri.path}?${request.requestedUri.query}',
        ),
      );
    }

    try {
      final ogId =
          request.requestedUri.queryParameters['id'] ??
          (throw const IdWrongException());
      final html = await renderComponent(
        SharedViewDocument(
          entity: switch (ogId[0]) {
            'B' => await _beaconRepository.getBeaconById(beaconId: ogId),
            'C' => await _commentRepository.getCommentById(ogId),
            'I' => await _invitationCase.fetchById(invitationId: ogId),
            'O' => await _opinionCase.getOpinionById(ogId),
            'U' => await _userRepository.getById(ogId),
            _ => throw IdWrongException(id: ogId),
          },
        ),
      );
      return Response(
        html.statusCode,
        body: html.body,
        headers: html.headers,
      );
    } on IdWrongException catch (e) {
      return Response.badRequest(body: e.toString());
    } on IdNotFoundException catch (e) {
      return Response.badRequest(body: e.toString());
    } catch (e) {
      return Response.internalServerError();
    }
  }
}
