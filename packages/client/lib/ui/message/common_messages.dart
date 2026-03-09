import 'package:tentura_root/domain/entity/localizable.dart';

final class OkMessage extends LocalizableMessage {
  const OkMessage();

  @override
  String get toEn => 'Ok';

  @override
  String get toRu => 'Ок';
}

final class NoValidSeedMessage extends LocalizableMessage {
  const NoValidSeedMessage();

  @override
  String get toEn => 'There is no valid seed in clipboard';

  @override
  String get toRu => 'В буфере обмена нет корректной seed-фразы';
}

final class NoValidCodeMessage extends LocalizableMessage {
  const NoValidCodeMessage();

  @override
  String get toEn => 'There is no valid code in clipboard';

  @override
  String get toRu => 'В буфере обмена нет подходящего кода';
}

final class LinkCopiedToClipboardMessage extends LocalizableMessage {
  const LinkCopiedToClipboardMessage();

  @override
  String get toEn => 'The link has been copied to the clipboard';

  @override
  String get toRu => 'Ссылка скопирована в буфер обмена';
}
