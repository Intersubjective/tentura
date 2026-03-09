import 'package:tentura_root/domain/entity/localizable.dart';

final class ComplaintSentMessage extends LocalizableMessage {
  const ComplaintSentMessage();

  @override
  String get toEn => 'Complaint Sent';

  @override
  String get toRu => 'Жалоба отправлена';
}
