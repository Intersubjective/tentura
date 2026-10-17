import 'package:intl/intl.dart';

import 'package:tentura/ui/message/action_message_base.dart';

/// After "Extend review": the request's new deadline (#380).
final class ReviewExtendedMessage extends LocalizableMessage {
  const ReviewExtendedMessage(this.closesAt);

  final DateTime closesAt;

  @override
  String get toEn => 'Deadline extended to ${_format('en')}';

  @override
  String get toRu => 'Срок продлён до ${_format('ru')}';

  /// Same format as the closure footer's deadline line.
  String _format(String locale) =>
      DateFormat.MMMd(locale).add_Hm().format(closesAt.toLocal());
}
