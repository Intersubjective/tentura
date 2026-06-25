import 'package:tentura_root/domain/entity/localizable.dart';

final class ComplaintSentMessage extends LocalizableMessage {
  const ComplaintSentMessage();

  @override
  String get toEn => 'Complaint Sent';

  @override
  String get toRu => 'Жалоба отправлена';
}

final class AccountDeletionRequestSentMessage extends LocalizableMessage {
  const AccountDeletionRequestSentMessage();

  @override
  String get toEn => 'Deletion request sent';

  @override
  String get toRu => 'Запрос на удаление отправлен';
}
