import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../exception.dart';
import '../port/email_discoverability_port.dart';
import '../util/email_auth_util.dart';

@lazySingleton
final class ContactCheckCase {
  const ContactCheckCase(this._checks, this._logger);

  final EmailDiscoverabilityPort _checks;
  final Logger _logger;

  Future<bool> checkEmail(String callerId, String value) async {
    final answer = await checkNormalizedEmail(
      callerId,
      normalizeAuthEmail(value),
    );
    if (answer == null) throw const RateLimitedException();
    if (answer.reachedDailyLimit) logDailyLimit(callerId);
    return answer.alreadyOnTentura;
  }

  Future<ContactCheckAnswer?> checkNormalizedEmail(
    String callerId,
    String email,
  ) => _checks.checkEmail(callerId, email);

  /// Called after the transaction that used the last check commits.
  void logDailyLimit(String callerId) =>
      _logger.warning('contact_check_daily_limit_reached user_id=$callerId');
}
