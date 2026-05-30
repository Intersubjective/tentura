import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/credential_case.dart';

/// `/api/v2/accounts/me/credentials` — authenticated credential management for
/// the calling account (`jwt.sub`). All routes are guarded by `verifyBearerJwt`
/// in `root_router`.
///
/// - `GET`    — list the account's credentials.
/// - `POST`   — link a new `ed25519_device` credential; body `{authRequestToken}`.
///              Conflict (pair already linked) → 409.
/// - `DELETE /<credentialId>` — remove a credential; last one → 409, unknown → 404.
@Injectable(order: 3)
final class AccountCredentialsController {
  const AccountCredentialsController(this._credentialCase);

  final CredentialCase _credentialCase;

  Future<Response> list(Request request) async {
    final accountId = _accountId(request);
    if (accountId == null) return Response.unauthorized(null);
    try {
      final credentials = await _credentialCase.list(accountId: accountId);
      return _json({
        'credentials': credentials.map(_credentialToMap).toList(),
      });
    } on ExceptionBase catch (e) {
      return _error(e);
    } catch (_) {
      return Response.internalServerError();
    }
  }

  Future<Response> link(Request request) async {
    final accountId = _accountId(request);
    if (accountId == null) return Response.unauthorized(null);

    final Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }

    final authRequestToken = body['authRequestToken'] as String?;
    if (authRequestToken == null || authRequestToken.isEmpty) {
      return Response.badRequest(body: 'authRequestToken is required');
    }

    try {
      final credential = await _credentialCase.linkDevice(
        accountId: accountId,
        authRequestToken: authRequestToken,
      );
      return _json(_credentialToMap(credential));
    } on CredentialConflictException catch (e) {
      return _error(e, status: 409);
    } on ExceptionBase catch (e) {
      return _error(e);
    } catch (_) {
      return Response.internalServerError();
    }
  }

  Future<Response> remove(Request request) async {
    final accountId = _accountId(request);
    if (accountId == null) return Response.unauthorized(null);

    final credentialId = request.params['credentialId'] ?? '';
    if (credentialId.isEmpty) {
      return Response.badRequest(body: 'missing credential id');
    }

    try {
      await _credentialCase.remove(
        accountId: accountId,
        credentialId: credentialId,
      );
      return _json({'ok': true});
    } on LastCredentialException catch (e) {
      return _error(e, status: 409);
    } on IdNotFoundException catch (e) {
      return _error(e, status: 404);
    } on ExceptionBase catch (e) {
      return _error(e);
    } catch (_) {
      return Response.internalServerError();
    }
  }

  //
  //
  String? _accountId(Request request) {
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    return (jwt == null || jwt.sub.isEmpty) ? null : jwt.sub;
  }

  Map<String, Object?> _credentialToMap(AccountCredentialEntity c) => {
    'id': c.id,
    'type': c.type.wire,
    'identifier': c.identifier,
    'createdAt': c.createdAt?.toIso8601String(),
  };

  Response _json(Object body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {kHeaderContentType: 'application/json'},
  );

  Response _error(ExceptionBase e, {int status = 400}) =>
      _json(e.toMap, status: status);
}
