import 'package:tentura_root/domain/entity/localizable.dart';

export 'package:tentura_root/domain/entity/localizable.dart';

abstract class LocalizableActionMessage extends LocalizableMessage {
  const LocalizableActionMessage();

  LocalizableMessage get label;

  void Function() get onPressed;
}
