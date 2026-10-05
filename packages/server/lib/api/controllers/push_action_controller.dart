import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/use_case/push_action_case.dart';

import '_base_controller.dart';

/// `POST /api/v2/push-action` — a plan notification button («Готово» /
/// «Понятно») posted by the service worker (plan §5.9, P2).
///
/// Body: `{"token": "<signed action token>"}`. The token is the only
/// credential. Responses: 200 `{"status":"ok"|"already"}`, 409
/// `{"status":"stale","code":"planActionStale"}`, 401 for a bad token, 400
/// for a bad body; any other method is 405.
@Injectable(order: 3)
final class PushActionController extends BaseController {
  const PushActionController(super.env, this._case);

  final PushActionCase _case;

  static const path = '/api/v2/push-action';

  /// Bodies are a token and nothing else.
  static const _maxBodyBytes = 4096;

  Future<Response> post(Request request) async {
    final token = await _readToken(request);
    if (token == null) {
      return _json(400, {'status': 'bad_request'});
    }
    return switch (await _case.apply(token)) {
      PushActionOutcome.applied => _json(200, {'status': 'ok'}),
      PushActionOutcome.alreadyDone => _json(200, {'status': 'already'}),
      PushActionOutcome.stale => _json(409, {
        'status': 'stale',
        'code': 'planActionStale',
      }),
      PushActionOutcome.invalid => _json(401, {'status': 'invalid'}),
    };
  }

  Response methodNotAllowed(Request request) => Response(
    405,
    body: 'Method Not Allowed',
    headers: {'Allow': 'POST', kHeaderCacheControl: kCacheControlNoStore},
  );

  Future<String?> _readToken(Request request) async {
    try {
      final bytes = await readBodyAsBytes(request.read);
      if (bytes.length > _maxBodyBytes) return null;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final token = decoded['token'];
      return token is String && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }

  Response _json(int status, Map<String, Object?> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {
      kHeaderContentType: kContentApplicationJson,
      kHeaderCacheControl: kCacheControlNoStore,
    },
  );

  @override
  Future<Response> handler(Request request) => post(request);
}
