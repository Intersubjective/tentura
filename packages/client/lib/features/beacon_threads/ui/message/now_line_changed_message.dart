import 'package:tentura_root/domain/entity/localizable.dart';

/// B085: a save from the "Update plan" sheet or "use message as plan" was
/// refused because someone changed the next step meanwhile. That editor has
/// already closed, so the way to replace the line is to open it again.
final class NowLineChangedElsewhereMessage extends LocalizableMessage {
  const NowLineChangedElsewhereMessage({required this.currentLine});

  /// The next step as it is on the server now.
  final String currentLine;

  @override
  String get toEn =>
      'Someone changed the next step meanwhile: “$currentLine”. '
      'Open “Update plan” to replace it.';

  @override
  String get toRu =>
      'Тем временем следующий шаг изменили: «$currentLine». '
      'Откройте «Обновить план», чтобы заменить его.';
}
