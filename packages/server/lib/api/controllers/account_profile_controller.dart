import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';

/// `/api/v2/accounts/me/profile` — minimal profile read/update for the calling
/// account. Guarded by `extractJwtOrSessionClaims` in `root_router`: Bearer JWT
/// or the `__Host-` session cookie both work, so the static landing drives the
/// post-signup name step without ever touching JWTs.
///
/// CSRF: the session cookie is `SameSite=Lax` (a cross-site PATCH carries no
/// cookie) and the endpoint accepts a JSON body only, which plain HTML forms
/// cannot produce.
///
/// - `GET`   — `{id, displayName}` of the calling account.
/// - `PATCH` — body `{displayName}`; trimmed,
///             [kTitleMinLength]–[kTitleMaxLength] chars.
@Injectable(order: 3)
final class AccountProfileController {
  // UserCase is an async-preResolved singleton; constructor injection would
  // make this controller (and RootRouter) async in generated DI and then fail
  // at runtime (`getAsync` on an already-resolved instance). Lazy GetIt lookup
  // matches MutationUser, the other UserCase consumer.
  AccountProfileController({UserCase? userCase})
    : _userCase = userCase ?? GetIt.I<UserCase>();

  final UserCase _userCase;

  Future<Response> get(Request request) async {
    final accountId = _accountId(request);
    if (accountId == null) return Response.unauthorized(null);
    try {
      final user = await _userCase.getProfile(id: accountId);
      return _json(_profileToMap(user));
    } on ExceptionBase catch (e) {
      return _error(e);
    } catch (_) {
      return Response.internalServerError();
    }
  }

  Future<Response> patch(Request request) async {
    final accountId = _accountId(request);
    if (accountId == null) return Response.unauthorized(null);

    final Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }

    final displayName = switch (body['displayName']) {
      final String s => s.trim(),
      _ => null,
    };
    if (displayName == null ||
        displayName.length < kTitleMinLength ||
        displayName.length > kTitleMaxLength) {
      return _json(
        {
          'error':
              'displayName must be $kTitleMinLength-$kTitleMaxLength '
              'characters',
        },
        status: 400,
      );
    }

    try {
      final user = await _userCase.updateProfile(
        id: accountId,
        displayName: displayName,
      );
      return _json(_profileToMap(user));
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

  Map<String, Object?> _profileToMap(UserEntity user) => {
    'id': user.id,
    'displayName': user.displayName,
  };

  Response _json(Object body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {kHeaderContentType: 'application/json'},
  );

  Response _error(ExceptionBase e, {int status = 400}) =>
      _json(e.toMap, status: status);
}
