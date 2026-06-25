import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/data/service/email/email_sink_writer.dart';

import '../http/cookies.dart';
import '_base_controller.dart';

/// Development/staging-only access to the latest file-sink email for an
/// allowlisted QA address.
@Injectable(order: 3)
final class QaEmailSinkController extends BaseController {
  const QaEmailSinkController(super.env);

  Future<Response> latestEmail(Request request) async {
    if (!_qaAllowed(request)) {
      return Response.notFound(null);
    }

    final rawEmail = request.url.queryParameters['email'] ?? '';
    final email = _normalizeQaEmail(rawEmail);
    if (email == null) {
      return Response.badRequest(body: 'invalid QA email');
    }

    final fileName = EmailSinkWriter.sanitizeEmailForFileName(email);
    final file = File('${env.qaEmailCaptureDir}/$fileName.json');
    if (!file.existsSync()) {
      return Response.ok(
        jsonEncode({
          'found': false,
          'email': email,
        }),
        headers: _jsonNoStore,
      );
    }

    Map<String, dynamic> payload;
    try {
      payload = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      return Response.internalServerError(
        body: 'invalid debug sink payload',
      );
    }

    final payloadEmail = payload['to'];
    if (payloadEmail is! String || payloadEmail.toLowerCase() != email) {
      return Response.internalServerError(
        body: 'debug sink email mismatch',
      );
    }

    return Response.ok(
      jsonEncode({
        'found': true,
        'email': email,
        'kind': payload['kind'],
        'verifyUrl': payload['verifyUrl'],
        'sentAt': payload['sentAt'],
      }),
      headers: _jsonNoStore,
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
    final email = raw.trim().toLowerCase();
    final parts = email.split('@');
    if (parts.length != 2) {
      return null;
    }
    final local = parts[0];
    final domain = parts[1];
    if (local.isEmpty ||
        domain.isEmpty ||
        !env.qaEmailDomains.contains(domain)) {
      return null;
    }
    return email;
  }

  Map<String, String> get _jsonNoStore => {
    kHeaderContentType: kContentApplicationJson,
    kHeaderCacheControl: kCacheControlNoStore,
  };

  @override
  Future<Response> handler(Request request) => latestEmail(request);
}
