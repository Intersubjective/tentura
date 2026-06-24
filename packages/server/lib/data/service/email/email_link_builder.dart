import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/email_link_port.dart';
import 'package:tentura_server/domain/unsubscribe/unsubscribe_token.dart';
import 'package:tentura_server/env.dart';

/// Builds absolute email links: deep links, manage-preferences, and signed
/// one-click unsubscribe URLs.
@LazySingleton(as: EmailLinkPort)
class EmailLinkBuilder implements EmailLinkPort {
  EmailLinkBuilder(this._env)
      : _token = UnsubscribeToken(_env.unsubscribeSigningSecret);

  final Env _env;
  final UnsubscribeToken _token;

  /// Resolves a relative deep link (e.g. `/#/beacon/...`) to an absolute URL.
  String absolute(String path) =>
      path.startsWith('http') ? path : '${_env.publicOrigin}$path';

  /// Opens the in-app notification settings.
  String manageUrl() => '${_env.publicOrigin}/#/notifications';

  /// Signed one-click unsubscribe URL. [scope] is a category name or `all`.
  String unsubscribeUrl({required String accountId, required String scope}) {
    final token = _token.sign(accountId: accountId, scope: scope);
    return '${_env.publicOrigin}/email/unsubscribe?token=$token';
  }
}
