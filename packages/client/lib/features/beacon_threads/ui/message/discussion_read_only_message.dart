import 'package:tentura_root/domain/entity/localizable.dart';

/// Shown when a write is blocked because the request discussion is read-only.
final class DiscussionReadOnlyMessage extends LocalizableMessage {
  const DiscussionReadOnlyMessage();

  @override
  String get toEn => 'This discussion is read-only.';

  @override
  String get toRu => 'Это обсуждение доступно только для чтения.';
}

/// Shown when plan/NOW-line update is blocked (request not open for coordination).
final class DiscussionPlanUpdateBlockedMessage extends LocalizableMessage {
  const DiscussionPlanUpdateBlockedMessage();

  @override
  String get toEn => 'Request is not open.';

  @override
  String get toRu => 'Запрос не открыт.';
}
