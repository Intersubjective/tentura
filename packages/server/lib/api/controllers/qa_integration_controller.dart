import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/util/email_auth_util.dart';

import '_base_controller.dart';
import '../http/cookies.dart';
import 'websocket/session/qa_realtime_socket_gate.dart';

@Injectable(order: 3)
final class QaIntegrationController extends BaseController {
  const QaIntegrationController(
    super.env,
    this._emailAuthCase,
    this._userRepository,
    this._invitationCase,
    this._friendshipLookup,
    this._realtimeSocketGate,
  );

  final EmailAuthCase _emailAuthCase;
  final UserRepositoryPort _userRepository;
  final InvitationCase _invitationCase;
  final VoteUserFriendshipLookupPort _friendshipLookup;
  final QaRealtimeSocketGate _realtimeSocketGate;

  Future<Response> bootstrap(Request request) async {
    if (!_qaAllowed(request)) {
      return Response.notFound(null);
    }

    Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }

    final runId = (body['runId'] as String? ?? '').trim().toLowerCase();
    if (runId.isEmpty) {
      return Response.badRequest(body: 'runId is required');
    }
    if (!RegExp(r'^[a-z0-9_-]{3,64}$').hasMatch(runId)) {
      return Response.badRequest(body: 'runId must match [a-z0-9_-]{3,64}');
    }

    final authorEmail = _normalizeQaEmail(
      body['authorEmail'] as String? ?? 'it-author-$runId@test.tentura.local',
    );
    final helperEmail = _normalizeQaEmail(
      body['helperEmail'] as String? ?? 'it-helper-$runId@test.tentura.local',
    );
    if (authorEmail == null || helperEmail == null) {
      return Response.badRequest(body: 'invalid QA email');
    }

    final author = await _ensureQaUser(authorEmail);
    final helper = await _ensureQaUser(helperEmail);
    _realtimeSocketGate
      ..registerBootstrappedUser(author.id)
      ..registerBootstrappedUser(helper.id);
    await _ensureFriendship(author: author, helper: helper, runId: runId);

    return Response.ok(
      jsonEncode({
        'authorEmail': authorEmail,
        'authorUserId': author.id,
        'helperEmail': helperEmail,
        'helperUserId': helper.id,
      }),
      headers: _jsonNoStore,
    );
  }

  Future<Response> realtimeSocket(Request request) async {
    if (!_qaAllowed(request)) {
      return Response.notFound(null);
    }

    Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }

    final userId = (body['userId'] as String? ?? '').trim();
    final action = (body['action'] as String? ?? '').trim();
    if (!_realtimeSocketGate.wasBootstrapped(userId)) {
      return Response.forbidden('user was not issued by QA bootstrap');
    }

    final sessionsClosed = switch (action) {
      'suspend' => await _realtimeSocketGate.suspendAndClose(userId),
      'resume' => () {
        _realtimeSocketGate.resume(userId);
        return 0;
      }(),
      _ => -1,
    };
    if (sessionsClosed < 0) {
      return Response.badRequest(body: 'action must be suspend or resume');
    }

    return Response.ok(
      jsonEncode({
        'userId': userId,
        'suspended': _realtimeSocketGate.isAuthenticationSuspended(userId),
        'sessionsClosed': sessionsClosed,
      }),
      headers: _jsonNoStore,
    );
  }

  Future<UserEntity> _ensureQaUser(String normalizedEmail) async {
    await _emailAuthCase.qaTestLogin(normalizedEmail: normalizedEmail);
    return _userRepository.getByCredential(
      type: CredentialType.emailOtp.wire,
      identifier: normalizedEmail,
    );
  }

  Future<void> _ensureFriendship({
    required UserEntity author,
    required UserEntity helper,
    required String runId,
  }) async {
    final alreadyFriends = await _friendshipLookup.isReciprocalSubscribe(
      viewerId: author.id,
      peerId: helper.id,
    );
    if (alreadyFriends) {
      return;
    }
    // Contact names are capped at 32 chars (ContactCase.normalizeName);
    // runIds carry a microsecond suffix, so clamp instead of embedding it all.
    final addresseeName = 'IT helper $runId';
    final invitation = await _invitationCase.create(
      userId: author.id,
      addresseeName: addresseeName.length <= 32
          ? addresseeName
          : addresseeName.substring(0, 32),
    );
    await _invitationCase.acceptAsExisting(
      code: invitation.id,
      userId: helper.id,
    );
  }

  bool _qaAllowed(Request request) {
    if (!env.isQaAuthEnabled) {
      return false;
    }
    final queryToken = request.url.queryParameters['_qa_token'];
    final authorization = request.headers['authorization'] ?? '';
    final bearerToken = authorization.toLowerCase().startsWith('bearer ')
        ? authorization.substring(7).trim()
        : null;
    return queryToken == env.qaAuthToken || bearerToken == env.qaAuthToken;
  }

  String? _normalizeQaEmail(String raw) {
    final normalized = normalizeAuthEmail(raw);
    if (!isValidAuthEmailFormat(normalized) ||
        !env.isQaEmailDomain(normalized)) {
      return null;
    }
    return normalized;
  }

  Map<String, String> get _jsonNoStore => {
    kHeaderContentType: kContentApplicationJson,
    kHeaderCacheControl: kCacheControlNoStore,
  };

  @override
  Future<Response> handler(Request request) => bootstrap(request);
}
