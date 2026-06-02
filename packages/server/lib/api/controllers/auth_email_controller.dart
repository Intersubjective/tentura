import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/api/http/email_auth_failure_page.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';

import '_base_controller.dart';

@Injectable(order: 3)
final class AuthEmailController extends BaseController {
  const AuthEmailController(
    super.env,
    this._emailAuthCase,
    this._sessionCase,
  );

  final EmailAuthCase _emailAuthCase;
  final SessionCase _sessionCase;

  /// `POST /api/v2/auth/email/start`
  Future<Response> start(Request request) async {
    Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }
    final email = body['email'] as String? ?? '';
    final inviteCode = body['inviteCode'] as String?;
    await _emailAuthCase.start(
      email: email,
      inviteCode: inviteCode,
      ipFingerprint: _clientIp(request),
      userAgentFingerprint: request.headers['user-agent'] ?? '',
    );
    return Response.ok(
      jsonEncode({'ok': true}),
      headers: {
        kHeaderContentType: kContentApplicationJson,
        kHeaderCacheControl: kCacheControlNoStore,
      },
    );
  }

  /// `GET /auth/email/verify?t=...`
  Future<Response> verify(Request request) async {
    final token = request.url.queryParameters['t'] ?? '';
    try {
      final result = await _emailAuthCase.verify(token);
      final sessionToken = await _sessionCase.createSession(
        accountId: result.accountId,
      );
      final destination = _redirectAfterVerify(result.inviteCode);
      return Response.found(
        destination,
        headers: withSetCookie(
          {kHeaderCacheControl: kCacheControlNoStore},
          buildSetCookie(
            name: _sessionCase.sessionCookieName(),
            value: sessionToken,
            maxAgeSeconds: _sessionCase.sessionCookieMaxAge().inSeconds,
          ),
        ),
      );
    } on EmailAuthTokenInvalidException {
      return Response(
        400,
        body: renderEmailAuthFailurePage(),
        headers: {
          kHeaderContentType: 'text/html; charset=utf-8',
          kHeaderCacheControl: kCacheControlNoStore,
        },
      );
    } catch (_) {
      return Response(
        400,
        body: renderEmailAuthFailurePage(),
        headers: {
          kHeaderContentType: 'text/html; charset=utf-8',
          kHeaderCacheControl: kCacheControlNoStore,
        },
      );
    }
  }

  String _redirectAfterVerify(String? inviteCode) {
    if (inviteCode != null && inviteCode.isNotEmpty) {
      return Uri.parse(env.publicOrigin)
          .replace(
            path: '/invite/$inviteCode',
            queryParameters: {'signed_in': '1'},
          )
          .toString();
    }
    final origin = env.publicOrigin.endsWith('/')
        ? env.publicOrigin
        : '${env.publicOrigin}/';
    return origin;
  }

  static String _clientIp(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    return 'unknown';
  }

  @override
  Future<Response> handler(Request request) =>
      throw UnsupportedError('use start/verify');
}
