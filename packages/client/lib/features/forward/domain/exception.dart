import 'package:tentura_root/domain/entity/localizable.dart';

sealed class ForwardException extends LocalizableException {
  const ForwardException();
}

final class IneligibleRecipientsException extends ForwardException {
  const IneligibleRecipientsException();

  @override
  String get toEn => 'Some recipients cannot receive forwards';

  @override
  String get toRu => 'Некоторые получатели не могут принять пересылку';
}
