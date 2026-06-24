import 'package:injectable/injectable.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/api/http/unsubscribe_page.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/use_case/unsubscribe_case.dart';

import '_base_controller.dart';

/// One-click email unsubscribe (RFC 8058 / CAN-SPAM / Gmail bulk-sender).
///
/// `GET` is scanner-safe: it only renders a confirmation form. `POST` actually
/// applies the unsubscribe (also the one-click `List-Unsubscribe-Post` target).
@Injectable(order: 3)
final class UnsubscribeController extends BaseController {
  const UnsubscribeController(super.env, this._unsubscribeCase);

  final UnsubscribeCase _unsubscribeCase;

  static const _postUrl = '/email/unsubscribe';

  Future<Response> getPage(Request request) async {
    final token = request.url.queryParameters['token'] ?? '';
    final payload = _unsubscribeCase.peek(token);
    if (payload == null) {
      return _html(400, renderUnsubscribeInvalidPage());
    }
    return _html(
      200,
      renderUnsubscribeConfirmPage(
        token: token,
        scope: payload.scope,
        postUrl: _postUrl,
      ),
    );
  }

  Future<Response> post(Request request) async {
    // One-click senders POST to the List-Unsubscribe URL (token in the query);
    // the confirmation form posts it in the body.
    var token = request.url.queryParameters['token'] ?? '';
    if (token.isEmpty) {
      token = await _readFormToken(request);
    }
    final scope = await _unsubscribeCase.apply(token);
    if (scope == null) {
      return _html(400, renderUnsubscribeInvalidPage());
    }
    return _html(
      200,
      renderUnsubscribeDonePage(
        scope: scope,
        manageUrl: '${env.publicOrigin}/#/notifications',
      ),
    );
  }

  Future<String> _readFormToken(Request request) async {
    try {
      final params = Uri.splitQueryString(await request.body.asString);
      return params['token'] ?? '';
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

  @override
  Future<Response> handler(Request request) => getPage(request);
}
