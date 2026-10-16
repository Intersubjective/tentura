import 'package:tentura_root/domain/entity/localizable.dart';

/// Someone else changed the request's next step while this person was
/// editing it (B085). Carries the line now on the server so the editor can
/// show it; saving again replaces it deliberately.
final class NowLineChangedException extends LocalizableException {
  const NowLineChangedException({required this.currentLine});

  /// The next step as it is on the server now.
  final String currentLine;

  @override
  String get toEn =>
      'Someone changed the next step while you were editing: '
      '“$currentLine”. Save again to replace it with yours.';

  @override
  String get toRu =>
      'Пока вы редактировали, следующий шаг изменили: '
      '«$currentLine». Сохраните ещё раз, чтобы заменить его своим.';
}
