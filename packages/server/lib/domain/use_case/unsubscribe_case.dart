import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/unsubscribe/unsubscribe_token.dart';
import 'package:tentura_server/env.dart';

/// Applies one-click email unsubscribes from a signed token.
@injectable
class UnsubscribeCase {
  UnsubscribeCase(this._preferences, Env env)
      : _token = UnsubscribeToken(env.unsubscribeSigningSecret);

  final NotificationPreferenceRepositoryPort _preferences;
  final UnsubscribeToken _token;

  /// Validates without mutating (for the GET confirmation page; scanner-safe).
  UnsubscribePayload? peek(String token) => _token.verify(token);

  /// Honors the unsubscribe. Returns the applied scope, or null when the token
  /// is invalid.
  Future<String?> apply(String token) async {
    final payload = _token.verify(token);
    if (payload == null) {
      return null;
    }
    final prefs = await _preferences.getForAccount(payload.accountId);
    if (payload.scope == 'all') {
      await _preferences.upsert(
        prefs.copyWith(
          emailCategories: const {},
          emailDigest: DigestCadence.off,
        ),
      );
    } else {
      final category = notificationCategoryFromName(payload.scope);
      await _preferences.upsert(
        prefs.copyWith(
          emailCategories: {...prefs.emailCategories}..remove(category),
        ),
      );
    }
    return payload.scope;
  }
}
