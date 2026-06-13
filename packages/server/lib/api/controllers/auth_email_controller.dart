import 'dart:convert';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/api/http/auth_invite_required_page.dart';
import 'package:tentura_server/api/http/email_auth_failure_page.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';

import '_base_controller.dart';

final _log = Logger('AuthEmailController');

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

  /// `POST /api/v2/auth/email/link/start` (Bearer) — add an email to the
  /// authenticated account. Unlike `/start` this bypasses the invite-only
  /// unregistered-email gate (the caller is already authenticated).
  Future<Response> linkStart(Request request) async {
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    if (jwt == null || jwt.sub.isEmpty) {
      return Response.unauthorized(null);
    }
    Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }
    final email = body['email'] as String? ?? '';
    await _emailAuthCase.start(
      email: email,
      linkAccountId: jwt.sub,
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

  /// `GET /auth/email/verify?t=...` — render confirmation only (scanner-safe).
  Future<Response> verifyGet(Request request) async {
    final token = request.url.queryParameters['t'] ?? '';
    if (token.isEmpty) {
      return _html(
        400,
        renderEmailAuthMissingPage(landingUrl: _landingUrl),
      );
    }
    final peek = await _emailAuthCase.peek(token);
    return switch (peek.status) {
      EmailAuthTokenStatus.valid => _html(
        200,
        renderEmailAuthConfirmPage(token: token, isLink: peek.isLink),
      ),
      EmailAuthTokenStatus.expired => _html(
        410,
        renderEmailAuthExpiredPage(
          landingUrl: _landingUrl,
          ttlMinutes: env.emailAuthTtl.inMinutes,
          inviteCode: peek.inviteCode,
        ),
      ),
      EmailAuthTokenStatus.consumed => _html(
        410,
        renderEmailAuthAlreadyUsedPage(
          landingUrl: _landingUrl,
          inviteCode: peek.inviteCode,
        ),
      ),
      EmailAuthTokenStatus.missing => _html(
        400,
        renderEmailAuthMissingPage(landingUrl: _landingUrl),
      ),
    };
  }

  /// `POST /auth/email/verify` — user-confirmed sign-in (consumes token last).
  Future<Response> verifyPost(Request request) async {
    final token = await _readFormToken(request);
    if (token.isEmpty) {
      return _html(
        400,
        renderEmailAuthMissingPage(landingUrl: _landingUrl),
      );
    }
    String? inviteCodeForRecovery;
    try {
      final peek = await _emailAuthCase.peek(token);
      inviteCodeForRecovery = peek.inviteCode;
      final outcome = await _emailAuthCase.confirm(token);
      return switch (outcome) {
        EmailAuthLoginConfirmed(
          :final sessionToken,
          :final inviteCode,
          :final isNewAccount,
        ) =>
          Response.found(
            _redirectAfterVerify(inviteCode, isNewAccount: isNewAccount),
            headers: withSetCookie(
              {kHeaderCacheControl: kCacheControlNoStore},
              buildSetCookie(
                name: _sessionCase.sessionCookieName(),
                value: sessionToken,
                maxAgeSeconds: _sessionCase.sessionCookieMaxAge().inSeconds,
              ),
            ),
          ),
        EmailAuthLinkConfirmed() => _html(
          200,
          renderEmailLinkedSuccessPage(),
        ),
      };
    } on EmailAuthTokenExpiredException {
      return _html(
        410,
        renderEmailAuthExpiredPage(
          landingUrl: _landingUrl,
          ttlMinutes: env.emailAuthTtl.inMinutes,
          inviteCode: inviteCodeForRecovery,
        ),
      );
    } on EmailAuthTokenAlreadyUsedException {
      return _html(
        410,
        renderEmailAuthAlreadyUsedPage(
          landingUrl: _landingUrl,
          inviteCode: inviteCodeForRecovery,
        ),
      );
    } on EmailAuthTokenMissingException {
      return _html(
        400,
        renderEmailAuthMissingPage(landingUrl: _landingUrl),
      );
    } on CredentialConflictException {
      return _html(409, renderEmailLinkConflictPage());
    } on ContactConflictException {
      return _html(409, renderEmailLinkConflictPage());
    } on OidcInviteRequiredException {
      return _inviteRequiredPage();
    } on InvitationWrongException catch (e) {
      return _inviteFailurePage(e, inviteCodeForRecovery);
    } on IdNotFoundException catch (e) {
      if (_looksLikeInviteFailure(e)) {
        return _inviteFailurePage(e, inviteCodeForRecovery);
      }
      return _internalPage(e, null, token);
    } on AmbiguousIdentityException {
      return _html(
        409,
        renderEmailAuthAmbiguousIdentityPage(landingUrl: _landingUrl),
      );
    } catch (e, st) {
      return _internalPage(e, st, token);
    }
  }

  Response _inviteFailurePage(Object e, String? inviteCode) {
    final desc = e is ExceptionBase ? e.description : e.toString();
    final lower = desc.toLowerCase();
    if (lower.contains('expired')) {
      return _html(
        409,
        renderEmailAuthInviteExpiredPage(
          landingUrl: _landingUrl,
          inviteCode: inviteCode,
        ),
      );
    }
    if (lower.contains('already used') || lower.contains('consumed')) {
      return _html(
        409,
        renderEmailAuthInviteUsedPage(
          landingUrl: _landingUrl,
          inviteCode: inviteCode,
        ),
      );
    }
    return _html(
      409,
      renderEmailAuthInviteInvalidPage(
        landingUrl: _landingUrl,
        inviteCode: inviteCode,
      ),
    );
  }

  bool _looksLikeInviteFailure(IdNotFoundException e) {
    final desc = e.description.toLowerCase();
    return desc.contains('invite') || desc.startsWith('id not found: [i');
  }

  Response _internalPage(Object e, StackTrace? st, String retryToken) {
    final traceId = _newTraceId();
    _log.severe('email auth confirm failed [$traceId]', e, st);
    final debug = env.isDebugModeOn
        ? '${e.runtimeType}: $e${st == null ? '' : '\n$st'}'
        : null;
    return _html(
      500,
      renderEmailAuthInternalPage(
        traceId: traceId,
        debugDetails: debug,
        retryToken: retryToken,
      ),
    );
  }

  String _newTraceId() {
    final bytes = List<int>.generate(8, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> _readFormToken(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    if (contentType.contains('application/x-www-form-urlencoded') ||
        contentType.contains('multipart/form-data')) {
      try {
        final params = Uri.splitQueryString(await request.body.asString);
        return params['t'] ?? '';
      } catch (_) {
        return '';
      }
    }
    try {
      final body = (await request.body.asJson as Map).cast<String, dynamic>();
      return body['t'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Response _html(int status, String body) => Response(
    status,
    body: body,
    headers: {
      kHeaderContentType: 'text/html; charset=utf-8',
      kHeaderCacheControl: kCacheControlNoStore,
    },
  );

  Response _inviteRequiredPage() => Response(
    403,
    body: renderAuthInviteRequiredPage(
      landingUrl: publicLandingUrl(env.publicOrigin),
    ),
    headers: {
      kHeaderContentType: 'text/html; charset=utf-8',
      kHeaderCacheControl: kCacheControlNoStore,
    },
  );

  String get _landingUrl => publicLandingUrl(env.publicOrigin);

  String _redirectAfterVerify(String? inviteCode, {required bool isNewAccount}) {
    if (inviteCode != null && inviteCode.isNotEmpty) {
      return Uri.parse(env.publicOrigin)
          .replace(
            path: '/invite/$inviteCode',
            queryParameters: {
              'signed_in': '1',
              if (isNewAccount) 'new': '1',
            },
          )
          .toString();
    }
    // New account without invite: `/` would route into WASM (cookie-presence
    // split, ADR 0002), so use the always-landing `/invite/` path for the
    // post-signup name + onboarding flow.
    if (isNewAccount) {
      return Uri.parse(env.publicOrigin)
          .replace(
            path: '/invite/',
            queryParameters: {'signed_in': '1', 'new': '1'},
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
      return forwarded.split(',').last.trim();
    }
    return 'unknown';
  }

  @override
  Future<Response> handler(Request request) =>
      throw UnsupportedError('use start/verifyGet/verifyPost');
}
