import 'package:injectable/injectable.dart';

import '_base_controller.dart';

/// Redirects `GET /shared/view?…` to the Flutter SPA hash route.
@Injectable(order: 3)
final class AppLinkRedirectController extends BaseController {
  const AppLinkRedirectController(super.env);

  @override
  Future<Response> handler(Request request) async {
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
}
