import 'package:tentura_root/domain/entity/localizable.dart';

/// Someone else changed the request's next step while this person was
/// editing it (B085, #517): the server refused the save because it was based
/// on an older revision. Carries the line on the server now so the editor can
/// show it; saving again on top of [currentRevision] replaces it on purpose.
final class NowLineChangedException extends LocalizableException {
  const NowLineChangedException({
    required this.currentLine,
    this.currentRevision = 0,
    this.updatedBy,
  });

  /// Server code 1348 (`beaconRoomNowLineConflict`).
  static const codeNumber = 1348;

  /// The next step as it is on the server now.
  final String currentLine;

  /// Its revision: the base for re-applying the person's own text.
  final int currentRevision;

  /// Who saved [currentLine], when the server said.
  final String? updatedBy;

  @override
  String get toEn =>
      'Someone changed the next step while you were editing: '
      '“$currentLine”. Save again to replace it with yours.';

  @override
  String get toRu =>
      'Пока вы редактировали, следующий шаг изменили: '
      '«$currentLine». Сохраните ещё раз, чтобы заменить его своим.';
}
